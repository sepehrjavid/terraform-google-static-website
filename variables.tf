variable "branches" {
  description = "Set of branch names that need deployment."
  type        = set(string)
}

variable "cicd" {
  description = "CI/CD configuration"
  type = object({
    enable                = optional(bool, true)
    existing_gh_conn_name = optional(string, null)
    github_config = optional(object({
      access_token                     = optional(string, null)
      existing_token_secret_version_id = optional(string, null)
      app_installation_id              = string
      repo_uri                         = string
    }), null)
  })
  validation {
    condition     = !var.cicd.enable || var.cicd.existing_gh_conn_name != null || var.cicd.github_config != null
    error_message = "Either github_config or existing_gh_conn_name must be provided when cicd.enable is set to true."
  }
  validation {
    condition     = var.cicd.github_config == null || var.cicd.github_config.access_token != null || var.cicd.github_config.existing_token_secret_version_id != null
    error_message = "When github_config is provided, either access_token or existing_token_secret_version_id must have a value."
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
