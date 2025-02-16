variable "branches" {
  description = "Set of branch names that need deployment."
  type        = set(string)
}

variable "github_config" {
  description = "GitHub configuration details."
  type = object({
    access_token        = string
    app_installation_id = string
    repo_uri            = string
  })
  sensitive = true
}

variable "enable_cicd" {
  description = "Enables CI/CD for automated deployments."
  type        = bool
  default     = true
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
    domain_name    = string
  })

  validation {
    condition     = !(var.dns_config.set_dns_config) || var.dns_config.zone_name != null
    error_message = "zone_name cannot be null when set_dns_config is set to true"
  }
}
