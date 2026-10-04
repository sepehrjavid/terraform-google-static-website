variable "branches" {
  description = "Set of branch names that need deployment."
  type        = set(string)

  validation {
    condition     = alltrue([for b in var.branches : can(regex("^[a-z]([a-z0-9-]*[a-z0-9])?$", b))])
    error_message = "Branch names are used in GCP resource names and DNS labels, so they must contain only lowercase letters, digits and hyphens, start with a letter and not end with a hyphen."
  }
  validation {
    condition     = alltrue([for b in var.branches : length("${var.name_prefix}-${b}-website-bucket") <= 63])
    error_message = "name_prefix and branch name are too long: bucket name \"<name_prefix>-<branch>-website-bucket\" must be at most 63 characters."
  }
}

variable "cicd" {
  description = "CI/CD configuration"
  type = object({
    enable                = optional(bool, true)
    existing_gh_conn_name = optional(string, null)
    build_config_filename = optional(string, "cloudbuild.yaml")
    repo_uri              = optional(string, null)
    build_sa_ids          = optional(map(string), null)
    github_config = optional(object({
      access_token                     = optional(string, null)
      access_token_version             = optional(number, 1)
      existing_token_secret_version_id = optional(string, null)
      app_installation_id              = string
    }), null)
  })
  validation {
    condition     = !var.cicd.enable || var.cicd.repo_uri != null
    error_message = "When cicd.enable is set to true, repo_uri must be specified."
  }
  validation {
    condition     = !var.cicd.enable || var.cicd.existing_gh_conn_name != null || var.cicd.github_config != null
    error_message = "Either github_config or existing_gh_conn_name must be provided when cicd.enable is set to true."
  }
  validation {
    condition     = var.cicd.github_config == null || (try(var.cicd.github_config.access_token, null) != null) != (try(var.cicd.github_config.existing_token_secret_version_id, null) != null)
    error_message = "When github_config is provided, set exactly one of access_token or existing_token_secret_version_id."
  }
  validation {
    condition     = try(var.cicd.github_config.existing_token_secret_version_id, null) == null || can(regex("^projects/[^/]+/secrets/[^/]+/versions/[^/]+$", var.cicd.github_config.existing_token_secret_version_id))
    error_message = "existing_token_secret_version_id must be in the format projects/{project}/secrets/{secret}/versions/{version}."
  }
  validation {
    condition     = !var.cicd.enable || var.cicd.build_sa_ids == null || length(setsubtract(var.branches, keys(var.cicd.build_sa_ids))) == 0
    error_message = "When cicd.enable is true, each branch in var.branches must have a corresponding key in cicd.build_sa_ids."
  }
  validation {
    condition     = !var.cicd.enable || var.cicd.build_sa_ids != null || alltrue([for b in var.branches : length("${var.name_prefix}-${b}-build") <= 30])
    error_message = "name_prefix and branch name are too long: service account ID \"<name_prefix>-<branch>-build\" must be at most 30 characters. Shorten them or provide cicd.build_sa_ids."
  }
}

variable "lb" {
  description = "Extra load balancer backends"
  type = object({
    extra_backends = optional(map(object({
      url_prefix   = string
      backend_id   = string
      strip_prefix = optional(bool, true)
    })))
  })
  default = {}
}

variable "name_prefix" {
  description = "Name prefix used to distinguish resources"
  type        = string
}

variable "project_id" {
  description = "The ID of the GCP project where resources are created."
  type        = string
}

variable "region" {
  description = "The GCP region for regional resources (buckets, Cloud Build connection, repository and triggers)."
  type        = string
}

variable "enable_cdn" {
  description = "Enables Cloud CDN for better performance."
  type        = bool
  default     = true
}

variable "enable_http_redirect" {
  description = "Enables HTTP to HTTPS redirection."
  type        = bool
  default     = true
}

variable "default_branch_name" {
  description = "The name of the default production branch."
  type        = string
  default     = "main"

  validation {
    condition     = contains(var.branches, var.default_branch_name)
    error_message = "default_branch_name (\"${var.default_branch_name}\") must be one of the branches in var.branches."
  }
}

variable "dns_config" {
  description = "Configuration for DNS settings."
  type = object({
    set_dns_config = optional(bool, false)
    zone_name      = optional(string, null)
    domain_name    = optional(string, null)
  })

  validation {
    condition     = !var.dns_config.set_dns_config || var.dns_config.zone_name != null
    error_message = "zone_name cannot be null when set_dns_config is set to true"
  }

  validation {
    condition     = var.dns_config.domain_name != null || var.dns_config.zone_name != null
    error_message = "Either domain_name or zone_name must be specified."
  }
}
