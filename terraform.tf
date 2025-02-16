terraform {
  required_version = ">= 1.10"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.17"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = ">= 6.17"
    }
  }
}
