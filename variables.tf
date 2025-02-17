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
      access_token        = string
      app_installation_id = string
      repo_uri            = string
    }), null)
  })
  # sensitive = true
  validation {
    condition     = !var.cicd.enable || var.cicd.existing_gh_conn_name != null || var.cicd.github_config != null
    error_message = "Either github_config or existing_gh_conn_name must be provided when cicd.enable is set to true."
  }
}

variable "name_prefix" {
  description = "Name prefix used to distinguish workloads"
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
    set_dns_config = optional(bool, true)
    zone_name      = optional(string, null)
    domain_name    = string
  })

  validation {
    condition     = !var.dns_config.set_dns_config || var.dns_config.zone_name != null
    error_message = "zone_name cannot be null when set_dns_config is set to true"
  }
}
