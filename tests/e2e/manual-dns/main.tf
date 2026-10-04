# No Cloud DNS zone (lab2.sepehrjavid.com isn't delegated): the module only
# outputs the records to create. Two branches, no CI/CD.

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

module "website" {
  source = "../../.."

  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  branches    = ["main", "dev"]
  cicd        = { enable = false }

  dns_config = {
    domain_name = "lab2.sepehrjavid.com"
  }
}

output "dns_auth_creds" {
  value = module.website.dns_auth_creds
}
