locals {
  domain_name = try(trim(data.google_dns_managed_zone.default_zone[0].dns_name, "."), var.dns_config.domain_name)
}
