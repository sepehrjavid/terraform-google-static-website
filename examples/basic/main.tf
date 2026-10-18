variable "project_id" {
  description = "GCP project to deploy the website into."
  type        = string
}

variable "region" {
  description = "Region for the website bucket."
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix for all resource names, e.g. my-site. Bucket names are global, so pick one nobody else uses."
  type        = string
}

variable "domain" {
  description = "Website domain, e.g. example.com. Its DNS can be hosted by any provider."
  type        = string
}

module "website" {
  # When copying this example, use source = "sepehrjavid/static-website/google" with version = "~> 3.0".
  source = "../.."

  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  branches    = ["main"]
  dns_config  = { domain_name = var.domain }
  cicd        = { enable = false }
}

output "lb_ip" {
  description = "Load balancer IP address. Point the domain's A record to it."
  value       = module.website.lb_ip
}

output "dns_auth_creds" {
  description = "Certificate validation record to create at your DNS provider."
  value       = module.website.dns_auth_creds
}

output "buckets" {
  description = "Bucket to upload the site to."
  value       = module.website.buckets
}
