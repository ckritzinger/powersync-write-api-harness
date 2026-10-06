#!/usr/bin/env bash
# Destroys the harness infrastructure with Terraform, then verifies nothing billable is left.
#
#   infra/scripts/teardown.sh                  # destroy + verify (asks once)
#   infra/scripts/teardown.sh --yes            # no prompt
#   infra/scripts/teardown.sh --check          # verify only, destroy nothing
#   infra/scripts/teardown.sh --region us-east-1 [--region ...]   # limit the check (default: all enabled regions)
#
# 1. `terraform destroy` for infra/ and, if it has state, infra/atlas.
# 2. A read-only sweep of the account that does not trust Terraform state: anything named with the
#    harness prefix or tagged Project=<name> (default write-api-harness; HARNESS_NAME overrides), in
#    every enabled region. The sweep never deletes; it lists leftovers and exits non-zero so you
#    can investigate (lost state, a failed destroy, resources from older harness versions).
set -uo pipefail

NAME="${HARNESS_NAME:-write-api-harness}"
INFRA="$(cd "$(dirname "$0")/.." && pwd)"
CHECK_ONLY=0
ASSUME_YES=0
REGIONS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --check) CHECK_ONLY=1 ;;
    --yes | -y) ASSUME_YES=1 ;;
    --region) REGIONS+=("$2"); shift ;;
    -h | --help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

say() { printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }

account="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" || {
  echo "AWS credentials not available (aws sts get-caller-identity failed)." >&2
  exit 2
}
if [ ${#REGIONS[@]} -eq 0 ]; then
  read -r -a REGIONS <<<"$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text)"
fi

say "Account:  $account"
say "Scope:    name prefix / Project tag '$NAME'"
say "Regions:  ${REGIONS[*]}"

# --- 1. Terraform destroy ---------------------------------------------------------------------

has_state() { [ -n "$(terraform -chdir="$1" state list 2>/dev/null)" ]; }
destroy_failed=0

if [ "$CHECK_ONLY" = 0 ]; then
  dirs=()
  for dir in "$INFRA" "$INFRA/atlas"; do has_state "$dir" && dirs+=("$dir"); done
  if [ ${#dirs[@]} -eq 0 ]; then
    say "No Terraform state with resources; nothing to destroy."
  else
    for dir in "${dirs[@]}"; do
      say "-- $dir: $(terraform -chdir="$dir" state list | wc -l | tr -d ' ') resources in state"
    done
    if [ "$ASSUME_YES" = 0 ]; then
      read -r -p "Destroy them? [y/N] " answer
      [ "$answer" = y ] || [ "$answer" = Y ] || { say "Aborted."; exit 1; }
    fi
    for dir in "${dirs[@]}"; do
      say "== terraform destroy ($dir)"
      extra=()
      if [ "$dir" = "$INFRA/atlas" ] && [ ! -f "$dir/terraform.tfvars" ]; then
        # project_id has no default; recover it from state so destroy works without a tfvars file.
        project_id="$(terraform -chdir="$dir" show -json 2>/dev/null |
          jq -r '[.values.root_module.resources[]? | .values.project_id? // empty][0] // empty')"
        [ -n "$project_id" ] && extra=(-var "project_id=$project_id")
      fi
      terraform -chdir="$dir" destroy -auto-approve -input=false ${extra[@]+"${extra[@]}"} || {
        destroy_failed=1
        warn "terraform destroy failed in $dir (Atlas needs MONGODB_ATLAS_PUBLIC_KEY/PRIVATE_KEY)."
      }
    done
  fi
fi

# --- 2. Verify (read-only) --------------------------------------------------------------------

say "== Verifying (read-only)"
found=0
# Prints a finding. Arguments: region, kind, tab/newline-separated identifiers (may be empty).
report() {
  [ -z "$3" ] && return
  found=1
  printf '%s\n' "$3" | tr '\t' '\n' | sed '/^$/d' | sed "s/^/  LEFTOVER [$1] $2: /"
}
tagged() { printf "length(%s[?Key=='Project' && Value=='%s']) > \`0\`" "$1" "$NAME"; }
q() { aws "$@" --output text 2>/dev/null; }

for r in "${REGIONS[@]}"; do
  f="Name=tag:Project,Values=$NAME"
  report "$r" "RDS instance" "$(q rds describe-db-instances --region "$r" \
    --query "DBInstances[?starts_with(DBInstanceIdentifier, '$NAME') || $(tagged TagList)].join(':', [DBInstanceIdentifier, DBInstanceStatus])")"
  report "$r" "RDS cluster" "$(q rds describe-db-clusters --region "$r" \
    --query "DBClusters[?starts_with(DBClusterIdentifier, '$NAME') || $(tagged TagList)].join(':', [DBClusterIdentifier, Status])")"
  report "$r" "RDS snapshot" "$(q rds describe-db-snapshots --region "$r" --snapshot-type manual \
    --query "DBSnapshots[?starts_with(DBSnapshotIdentifier, '$NAME') || starts_with(DBInstanceIdentifier, '$NAME')].DBSnapshotIdentifier")"
  report "$r" "RDS cluster snapshot" "$(q rds describe-db-cluster-snapshots --region "$r" --snapshot-type manual \
    --query "DBClusterSnapshots[?starts_with(DBClusterSnapshotIdentifier, '$NAME') || starts_with(DBClusterIdentifier, '$NAME')].DBClusterSnapshotIdentifier")"
  report "$r" "RDS retained automated backup" "$(q rds describe-db-instance-automated-backups --region "$r" \
    --query "DBInstanceAutomatedBackups[?starts_with(DBInstanceIdentifier, '$NAME')].join(':', [DBInstanceIdentifier, DbiResourceId])")"
  report "$r" "RDS subnet group" "$(q rds describe-db-subnet-groups --region "$r" \
    --query "DBSubnetGroups[?starts_with(DBSubnetGroupName, '$NAME')].DBSubnetGroupName")"
  report "$r" "RDS parameter group" "$(q rds describe-db-parameter-groups --region "$r" \
    --query "DBParameterGroups[?starts_with(DBParameterGroupName, '$NAME')].DBParameterGroupName")"
  report "$r" "EC2 instance" "$(q ec2 describe-instances --region "$r" --filters "$f" \
    Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId')"
  report "$r" "Elastic IP" "$(q ec2 describe-addresses --region "$r" --filters "$f" --query 'Addresses[].PublicIp')"
  report "$r" "ECR repository" "$(q ecr describe-repositories --region "$r" \
    --query "repositories[?starts_with(repositoryName, '$NAME')].repositoryName")"
  report "$r" "VPC" "$(q ec2 describe-vpcs --region "$r" --filters "$f" --query 'Vpcs[].VpcId')"
  report "$r" "security group" "$(q ec2 describe-security-groups --region "$r" --filters "$f" --query 'SecurityGroups[].GroupId')"
  # Anything else carrying the tag. The tagging API can list resources for a few minutes after
  # deletion, so treat these as hints when nothing above was found.
  report "$r" "tagged resource (may lag deletion)" "$(q resourcegroupstaggingapi get-resources --region "$r" \
    --tag-filters "Key=Project,Values=$NAME" --query 'ResourceTagMappingList[].ResourceARN')"
done
report global "IAM role" "$(q iam list-roles --query "Roles[?starts_with(RoleName, '$NAME')].RoleName")"
report global "IAM instance profile" "$(q iam list-instance-profiles \
  --query "InstanceProfiles[?starts_with(InstanceProfileName, '$NAME')].InstanceProfileName")"

for dir in "$INFRA" "$INFRA/atlas"; do
  has_state "$dir" && { found=1; say "  LEFTOVER Terraform state still lists resources in $dir"; }
done

if [ "$found" = 1 ] || [ "$destroy_failed" = 1 ]; then
  warn "Harness resources may still exist (listed above). The check deletes nothing;"
  warn "re-run terraform destroy, or remove them in the AWS console / Atlas UI."
  exit 1
fi
say "Clean: no harness resources found."
