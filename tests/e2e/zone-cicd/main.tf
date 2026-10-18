# Existing Cloud DNS zone with domain_name set to the zone's DNS name (trailing
# dot), CI/CD with a token the module stores and build SAs it creates, CDN on
# (so the build SAs get the cache invalidation role), HTTP redirect off and
# 404.html for unknown paths (not_found_page).

terraform {
  backend "gcs" {}
}

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

locals {
  name_prefix = "${var.name_prefix}zc"
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "app_installation_id" {
  type = string
}

module "website" {
  source = "../../.."

  project_id  = var.project_id
  region      = var.region
  name_prefix = local.name_prefix

  # No pushes happen to this branch, so the trigger never runs a build.
  branches             = ["e2e"]
  default_branch_name  = "e2e"
  enable_http_redirect = false
  not_found_page       = "404.html"

  cicd = {
    repo_uri = "https://github.com/sepehrjavid/terraform-google-static-website.git"
    github_config = {
      app_installation_id = var.app_installation_id
      access_token        = var.github_token
    }
  }

  dns_config = {
    set_dns_config = true
    zone_name      = "lab-sepehrjavid-com"
    domain_name    = "lab.sepehrjavid.com."
  }
}

output "buckets" {
  value = module.website.buckets
}
