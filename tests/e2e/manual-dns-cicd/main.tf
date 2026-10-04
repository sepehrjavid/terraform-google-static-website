# No Cloud DNS zone, CI/CD with a token already in Secret Manager and build SAs
# passed in through build_sa_ids.

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

variable "github_token" {
  type      = string
  sensitive = true
}

variable "app_installation_id" {
  type = string
}

resource "google_secret_manager_secret" "token" {
  project   = var.project_id
  secret_id = "${var.name_prefix}-token"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "token" {
  secret                 = google_secret_manager_secret.token.id
  secret_data_wo         = var.github_token
  secret_data_wo_version = 1
}

resource "google_service_account" "build" {
  project    = var.project_id
  account_id = "${var.name_prefix}-own-build"
}

module "website" {
  source = "../../.."

  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix

  # No pushes happen to this branch, so the trigger never runs a build.
  branches            = ["e2e"]
  default_branch_name = "e2e"

  cicd = {
    repo_uri     = "https://github.com/sepehrjavid/terraform-google-static-website.git"
    build_sa_ids = { e2e = google_service_account.build.id }
    github_config = {
      app_installation_id              = var.app_installation_id
      existing_token_secret_version_id = google_secret_manager_secret_version.token.id
    }
  }

  dns_config = {
    domain_name = "lab2.sepehrjavid.com"
  }
}

output "lb_ip" {
  value = module.website.lb_ip
}
