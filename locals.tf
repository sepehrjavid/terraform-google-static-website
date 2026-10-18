locals {
  domain_name = try(trim(data.google_dns_managed_zone.default_zone[0].dns_name, "."), trim(var.dns_config.domain_name, "."))

  domains = merge(
    { for b in var.branches : b => b == var.default_branch_name ? local.domain_name : "${b}.${local.domain_name}" },
    var.enable_www_redirect ? { www = "www.${local.domain_name}" } : {},
  )
}
