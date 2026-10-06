# Optional, separate root module: MongoDB source on Atlas (existing account) for engine = none.
# Atlas clusters are replica sets, which the write API's Mongo transactions require.
#
#   export MONGODB_ATLAS_PUBLIC_KEY=... MONGODB_ATLAS_PRIVATE_KEY=...
#   terraform -chdir=infra/atlas apply -var project_id=<atlas project id>
#
# Access is open to 0.0.0.0/0 by default (throwaway cluster, random password); destroy it after
# each run with infra/scripts/teardown.sh.

terraform {
  required_version = ">= 1.6"
  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 1.21"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

variable "project_id" {
  type = string
}

variable "name" {
  type    = string
  default = "write-api-harness"
}

variable "region" {
  description = "Atlas region name for the free cluster, e.g. US_EAST_1."
  type        = string
  default     = "US_EAST_1"
}

variable "access_cidrs" {
  description = "Atlas IP access list. Open by default; narrow to your IP + PowerSync egress IPs if it will live longer."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "db_name" {
  type    = string
  default = "harness"
}

resource "mongodbatlas_advanced_cluster" "main" {
  project_id   = var.project_id
  name         = var.name
  cluster_type = "REPLICASET"

  replication_specs {
    region_configs {
      provider_name         = "TENANT"
      backing_provider_name = "AWS"
      region_name           = var.region
      priority              = 7
      electable_specs {
        instance_size = "M0"
      }
    }
  }
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "mongodbatlas_database_user" "harness" {
  project_id         = var.project_id
  username           = "harness"
  password           = random_password.db.result
  auth_database_name = "admin"

  roles {
    role_name     = "readWrite"
    database_name = var.db_name
  }
  # collMod/create with validators (rake mongo:setup) needs dbAdmin on the harness database.
  roles {
    role_name     = "dbAdmin"
    database_name = var.db_name
  }
}

resource "mongodbatlas_project_ip_access_list" "access" {
  for_each   = toset(var.access_cidrs)
  project_id = var.project_id
  cidr_block = each.value
}

output "database_uri" {
  description = "DATABASE_URI (DATABASE_TYPE=mongodb) for the write API and the Rails app."
  value = format(
    "%s/%s?retryWrites=true&w=majority",
    replace(
      mongodbatlas_advanced_cluster.main.connection_strings[0].standard_srv,
      "mongodb+srv://",
      "mongodb+srv://harness:${random_password.db.result}@"
    ),
    var.db_name
  )
  sensitive = true
}
