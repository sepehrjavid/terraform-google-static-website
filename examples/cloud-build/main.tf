variable "project_id" {
  description = "GCP project to deploy the website into."
  type        = string
}

variable "region" {
  description = "Region for the buckets and the Cloud Build connection, repository and triggers."
  type        = string
  default     = "us-central1"
}

variable "name_prefix" {
  description = "Prefix for all resource names, e.g. my-site. Bucket names are global, so pick one nobody else uses. At most 16 characters, so the build service account ID <name_prefix>-develop-build fits in 30."
  type        = string
}

variable "zone_name" {
  description = "Cloud DNS managed zone in project_id whose DNS name is the website domain, e.g. example-com for example.com."
  type        = string
}

variable "repo_uri" {
  description = "GitHub repository of the site, e.g. https://github.com/owner/site.git."
  type        = string
}

variable "app_installation_id" {
  description = "Installation ID of the Cloud Build GitHub App, the number at the end of https://github.com/settings/installations/<id>."
  type        = string
}

variable "github_token" {
  description = "GitHub personal access token (classic) with the repo, read:user and read:org scopes. The module stores it in Secret Manager without saving it in the Terraform state."
  type        = string
  sensitive   = true
}

module "website" {
  # When copying this example, use source = "sepehrjavid/static-website/google" with version = "~> 2.0".
  source = "../.."

  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  branches    = ["main", "develop"]

  dns_config = {
    set_dns_config = true
    zone_name      = var.zone_name
  }

  cicd = {
    repo_uri = var.repo_uri
    github_config = {
      app_installation_id = var.app_installation_id
      access_token        = var.github_token
    }
  }
}

output "buckets" {
  description = "Bucket per branch. Each branch's build uploads to its own."
  value       = module.website.buckets
}

output "url_map_name" {
  description = "URL map whose CDN cache the builds invalidate."
  value       = module.website.url_map_name
}

output "build_sa" {
  description = "Email of the service account each branch's builds run as."
  value       = { for branch, sa in module.website.build_sa : branch => sa.email }
}

output "github_connection_name" {
  description = "Cloud Build GitHub connection. Pass it as cicd.existing_gh_conn_name to reuse it for another site in the same project and region."
  value       = module.website.github_connection_name
}
