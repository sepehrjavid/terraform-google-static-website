data "google_client_config" "client_config" {}
data "google_project" "project" {}
data "google_dns_managed_zone" "default_zone" {
  count = var.dns_config.zone_name != null ? 1 : 0
  name  = var.dns_config.zone_name
}
