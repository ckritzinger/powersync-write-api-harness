variable "region" {
  type    = string
  default = "us-east-1"
}

variable "name" {
  description = "Prefix for every resource."
  type        = string
  default     = "write-api-harness"
}

variable "engine" {
  description = "Source DB engine to run on RDS: postgres | mysql | sqlserver | none (none = MongoDB on Atlas, see infra/atlas)."
  type        = string
  default     = "postgres"
  validation {
    condition     = contains(["postgres", "mysql", "sqlserver", "none"], var.engine)
    error_message = "engine must be postgres, mysql, sqlserver or none."
  }
}

variable "db_ingress_cidrs" {
  description = <<-EOT
    Sources allowed to reach the database port. Open to the internet by default: these are
    throwaway databases with a random password, destroyed after each test run (scripts/teardown.sh),
    and the local write API, Rails app and the hosted PowerSync instance all need to reach them.
    Narrow it (your IP + PowerSync egress IPs) if a database will live longer.
  EOT
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "db_username" {
  type    = string
  default = "harness"
}

variable "db_name" {
  description = "Database name. SQL Server on RDS has no initial DB; create it with `bin/rails db:create`."
  type        = string
  default     = "harness"
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "postgres_force_ssl" {
  description = <<-EOT
    Require TLS on RDS Postgres. The write API's Postgres persister ignores sslmode in DATABASE_URI,
    so with this on it connects only if its environment sets PGSSLMODE=no-verify (node-postgres
    reads it; the RDS CA is not in Node's trust store, so require/verify-* fail). Off by default
    for zero-config runs; credentials then cross the internet in clear text.
  EOT
  type        = bool
  default     = false
}
