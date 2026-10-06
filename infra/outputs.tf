output "database_type" {
  description = "DATABASE_TYPE for both the write API and the Rails app."
  value       = local.rds_enabled ? local.db.scheme : "mongodb"
}

output "database_host" {
  value = local.rds_enabled ? aws_db_instance.main[0].address : ""
}

output "database_uri" {
  description = "DATABASE_URI for both the write API and the Rails app (empty for engine = none; use infra/atlas)."
  value = local.rds_enabled ? format(
    "%s://%s:%s@%s:%d/%s",
    local.db.scheme, var.db_username, random_password.db.result,
    aws_db_instance.main[0].address, local.db.port, var.db_name
  ) : ""
  sensitive = true
}
