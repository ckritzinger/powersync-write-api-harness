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
  # describe-regions answers from any region, but the CLI insists on one: use the configured region,
  # else us-east-1. (A profile without a default region is normal and must not break the script.)
  bootstrap="${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null)}}"
  bootstrap="${bootstrap:-us-east-1}"
  regions_text="$(aws ec2 describe-regions --region "$bootstrap" --query 'Regions[].RegionName' --output text)" || {
    echo "Could not list AWS regions (aws ec2 describe-regions --region $bootstrap failed)." >&2
    exit 2
  }
  read -r -a REGIONS <<<"$regions_text"
fi
[ ${#REGIONS[@]} -gt 0 ] || { echo "No regions to check (pass --region <name>)." >&2; exit 2; }

# Failed AWS queries are recorded here (a file, because queries run in $(...) subshells). A query
# that failed has not looked at anything, so the account must never be reported clean after one.
FAIL_LOG="$(mktemp)"
OUT_DIR="" # per-region results, created in the verify step
trap 'rm -f "$FAIL_LOG"; [ -n "$OUT_DIR" ] && rm -rf "$OUT_DIR"' EXIT

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
# Formats findings. Arguments: region, kind, tab/newline-separated identifiers (may be empty).
emit() {
  [ -z "$3" ] && return
  printf '%s\n' "$3" | tr '\t' '\n' | sed '/^$/d' | sed "s/^/  LEFTOVER [$1] $2: /"
}
# Same, but for the main shell: also remembers that something was found.
report() {
  [ -z "$3" ] && return
  found=1
  emit "$@"
}
tagged() { printf "length(%s[?Key=='Project' && Value=='%s']) > \`0\`" "$1" "$NAME"; }
# Runs one read-only query and prints its result. A failure prints nothing to stdout, but is reported
# on stderr and logged, so the verdict below cannot be "clean".
q() {
  local err out
  err="$(mktemp)"
  if out="$(aws "$@" --output text 2>"$err")"; then
    printf '%s' "$out"
  else
    printf 'CHECK FAILED: aws %s\n    %s\n' "$*" "$(head -n 1 "$err")" >&2
    printf '%s\n' "$*" >>"$FAIL_LOG"
  fi
  rm -f "$err"
}

# Every query for one region (about 13 AWS CLI calls). Runs in a background job: it only prints.
check_region() {
  local r="$1" f="Name=tag:Project,Values=$NAME"
  emit "$r" "RDS instance" "$(q rds describe-db-instances --region "$r" \
    --query "DBInstances[?starts_with(DBInstanceIdentifier, '$NAME') || $(tagged TagList)].join(':', [DBInstanceIdentifier, DBInstanceStatus])")"
  emit "$r" "RDS cluster" "$(q rds describe-db-clusters --region "$r" \
    --query "DBClusters[?starts_with(DBClusterIdentifier, '$NAME') || $(tagged TagList)].join(':', [DBClusterIdentifier, Status])")"
  emit "$r" "RDS snapshot" "$(q rds describe-db-snapshots --region "$r" --snapshot-type manual \
    --query "DBSnapshots[?starts_with(DBSnapshotIdentifier, '$NAME') || starts_with(DBInstanceIdentifier, '$NAME')].DBSnapshotIdentifier")"
  emit "$r" "RDS cluster snapshot" "$(q rds describe-db-cluster-snapshots --region "$r" --snapshot-type manual \
    --query "DBClusterSnapshots[?starts_with(DBClusterSnapshotIdentifier, '$NAME') || starts_with(DBClusterIdentifier, '$NAME')].DBClusterSnapshotIdentifier")"
  emit "$r" "RDS retained automated backup" "$(q rds describe-db-instance-automated-backups --region "$r" \
    --query "DBInstanceAutomatedBackups[?starts_with(DBInstanceIdentifier, '$NAME')].join(':', [DBInstanceIdentifier, DbiResourceId])")"
  emit "$r" "RDS subnet group" "$(q rds describe-db-subnet-groups --region "$r" \
    --query "DBSubnetGroups[?starts_with(DBSubnetGroupName, '$NAME')].DBSubnetGroupName")"
  emit "$r" "RDS parameter group" "$(q rds describe-db-parameter-groups --region "$r" \
    --query "DBParameterGroups[?starts_with(DBParameterGroupName, '$NAME')].DBParameterGroupName")"
  emit "$r" "EC2 instance" "$(q ec2 describe-instances --region "$r" --filters "$f" \
    Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId')"
  emit "$r" "Elastic IP" "$(q ec2 describe-addresses --region "$r" --filters "$f" --query 'Addresses[].PublicIp')"
  emit "$r" "ECR repository" "$(q ecr describe-repositories --region "$r" \
    --query "repositories[?starts_with(repositoryName, '$NAME')].repositoryName")"
  emit "$r" "VPC" "$(q ec2 describe-vpcs --region "$r" --filters "$f" --query 'Vpcs[].VpcId')"
  emit "$r" "security group" "$(q ec2 describe-security-groups --region "$r" --filters "$f" --query 'SecurityGroups[].GroupId')"
  # Anything else carrying the tag. The tagging API can list resources for a few minutes after
  # deletion, so treat these as hints when nothing above was found.
  emit "$r" "tagged resource (may lag deletion)" "$(q resourcegroupstaggingapi get-resources --region "$r" \
    --tag-filters "Key=Project,Values=$NAME" --query 'ResourceTagMappingList[].ResourceARN')"
}

# Regions are independent, so check several at once: sequentially this is minutes of silence.
JOBS="${CHECK_JOBS:-8}"
OUT_DIR="$(mktemp -d)"
say "Checking ${#REGIONS[@]} region(s), up to $JOBS at a time (about 13 AWS calls each)..."
running=0
for r in "${REGIONS[@]}"; do
  ( check_region "$r" >"$OUT_DIR/$r.txt"; printf '  [%s] checked\n' "$r" ) &
  running=$((running + 1))
  if [ "$running" -ge "$JOBS" ]; then wait; running=0; fi # bash 3.2 (macOS) has no `wait -n`
done
wait
for r in "${REGIONS[@]}"; do
  [ -s "$OUT_DIR/$r.txt" ] && { found=1; cat "$OUT_DIR/$r.txt"; }
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
  [ -s "$FAIL_LOG" ] && warn "$(wc -l <"$FAIL_LOG" | tr -d ' ') check(s) also failed (CHECK FAILED above), so the list may be incomplete."
  exit 1
fi
if [ -s "$FAIL_LOG" ]; then
  warn "$(wc -l <"$FAIL_LOG" | tr -d ' ') check(s) failed (CHECK FAILED above): nothing was found, but the account was NOT fully checked."
  warn "Fix the cause (credentials, permissions, or a region you cannot query) and re-run, or limit it with --region."
  exit 1
fi
say "Clean: no harness resources found."
