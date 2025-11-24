variable "branches" {
  description = "Set of branch names that need deployment."
  type        = set(string)
}

variable "cicd" {
  description = "CI/CD configuration"
  type = object({
    enable                = optional(bool, true)
    existing_gh_conn_name = optional(string, null)
    build_config_filename = optional(string, "cloudbuild.yaml")
    repo_uri              = optional(string, null)
    build_sa_emails       = optional(map(string), {})
    github_config = optional(object({
      access_token                     = optional(string, null)
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
    condition     = var.cicd.github_config == null || try(var.cicd.github_config.access_token, null) != null || try(var.cicd.github_config.existing_token_secret_version_id, null) != null
    error_message = "When github_config is provided, either access_token or existing_token_secret_version_id must have a value."
  }
  validation {
    condition     = !var.cicd.enable || length(setsubtract(var.branches, keys(var.cicd.build_sa_emails))) == 0
    error_message = "When cicd.enable is true, each branch in var.branches must have a corresponding key in cicd.build_sa_emails."
  }
}

variable "name_prefix" {
  description = "Name prefix used to distinguish resources"
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
    error_message = "Either domain_name or set_dns_config must be specified"
  }
}
