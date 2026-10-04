# Existing Cloud DNS zone (lab.sepehrjavid.com), two branches, an extra
# backend under /api, CDN and HTTP redirect on, no CI/CD.

variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "name_prefix" {
  type = string
}

resource "google_storage_bucket" "api" {
  project                     = var.project_id
  name                        = "${var.name_prefix}-api-website-bucket"
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
  }
}

resource "google_storage_bucket_iam_member" "api_public" {
  bucket = google_storage_bucket.api.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_compute_backend_bucket" "api" {
  project     = var.project_id
  name        = "${var.name_prefix}-api-backend"
  bucket_name = google_storage_bucket.api.name
}

module "website" {
  source = "../../.."

  project_id  = var.project_id
  region      = var.region
  name_prefix = var.name_prefix
  branches    = ["main", "dev"]
  cicd        = { enable = false }

  dns_config = {
    set_dns_config = true
    zone_name      = "lab-sepehrjavid-com"
  }

  lb = {
    extra_backends = {
      main = {
        url_prefix = "api"
        backend_id = google_compute_backend_bucket.api.id
      }
    }
  }
}

output "buckets" {
  value = module.website.buckets
}

output "api_bucket" {
  value = google_storage_bucket.api.name
}
