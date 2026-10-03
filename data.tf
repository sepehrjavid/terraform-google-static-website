data "google_project" "project" {
  project_id = var.project_id
}
data "google_dns_managed_zone" "default_zone" {
  count   = var.dns_config.zone_name != null ? 1 : 0
  project = var.project_id
  name    = var.dns_config.zone_name

  lifecycle {
    postcondition {
      condition     = var.dns_config.domain_name == null || trim(self.dns_name, ".") == var.dns_config.domain_name
      error_message = "domain_name must match the zone's DNS name. To host on a subdomain, create a delegated zone for it (e.g. www.example.com) and pass that as zone_name."
    }
  }
}