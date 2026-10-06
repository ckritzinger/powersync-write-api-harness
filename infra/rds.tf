locals {
  rds_enabled = var.engine != "none"

  engine_settings = {
    postgres  = { engine = "postgres", version = "16", port = 5432, family = "postgres16", scheme = "postgres" }
    mysql     = { engine = "mysql", version = "8.4", port = 3306, family = "mysql8.4", scheme = "mysql" }
    sqlserver = { engine = "sqlserver-ex", version = "16.00", port = 1433, family = "sqlserver-ex-16.0", scheme = "mssql" }
  }
  db = local.rds_enabled ? local.engine_settings[var.engine] : null

  # Settings PowerSync replication needs, per engine. SQL Server uses CDC instead (rake mssql:enable_cdc).
  db_parameters = {
    postgres = [
      { name = "rds.logical_replication", value = "1", apply_method = "pending-reboot" },
      # RDS Postgres 15+ defaults to forcing TLS. The write API's Postgres persister ignores sslmode
      # in DATABASE_URI; only node-postgres' PGSSLMODE env var turns TLS on. See var.postgres_force_ssl.
      { name = "rds.force_ssl", value = var.postgres_force_ssl ? "1" : "0", apply_method = "pending-reboot" }
    ]
    mysql = [
      { name = "binlog_format", value = "ROW", apply_method = "immediate" },
      { name = "gtid-mode", value = "ON", apply_method = "pending-reboot" },
      { name = "enforce_gtid_consistency", value = "ON", apply_method = "pending-reboot" }
    ]
    sqlserver = []
  }
}

resource "random_password" "db" {
  length  = 24
  special = false # goes into connection URIs unescaped
}

resource "aws_db_subnet_group" "main" {
  name       = var.name
  subnet_ids = aws_subnet.public[*].id
}

# The only cloud resource the harness needs: the write API, Rails app and frontend all run locally.
# Publicly addressable; db_ingress_cidrs defaults to the whole internet (throwaway databases).
resource "aws_security_group" "db" {
  name        = "${var.name}-db"
  description = "Source DB port from db_ingress_cidrs"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = local.rds_enabled ? [1] : []
    content {
      description = "local write API / read app, hosted PowerSync"
      from_port   = local.db.port
      to_port     = local.db.port
      protocol    = "tcp"
      cidr_blocks = var.db_ingress_cidrs
    }
  }
}

resource "aws_db_parameter_group" "main" {
  count  = local.rds_enabled ? 1 : 0
  name   = "${var.name}-${var.engine}"
  family = local.db.family

  dynamic "parameter" {
    for_each = local.db_parameters[var.engine]
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_instance" "main" {
  count                  = local.rds_enabled ? 1 : 0
  identifier             = "${var.name}-${var.engine}"
  engine                 = local.db.engine
  engine_version         = local.db.version
  instance_class         = var.db_instance_class
  allocated_storage      = 20
  storage_type           = "gp2"
  db_name                = var.engine == "sqlserver" ? null : var.db_name
  username               = var.db_username
  password               = random_password.db.result
  port                   = local.db.port
  license_model          = var.engine == "sqlserver" ? "license-included" : null
  parameter_group_name   = aws_db_parameter_group.main[0].name
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  publicly_accessible    = true
  # MySQL binlog replication needs automated backups; 1 day stays within the free tier.
  backup_retention_period = var.engine == "mysql" ? 1 : 0
  apply_immediately       = true
  skip_final_snapshot     = true
  deletion_protection     = false
}
