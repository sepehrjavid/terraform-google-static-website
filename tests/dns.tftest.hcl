mock_provider "google" {
  mock_data "google_dns_managed_zone" {
    defaults = { dns_name = "www.example.com." }
  }
}
mock_provider "time" {}

variables {
  project_id  = "p"
  region      = "europe-north2"
  name_prefix = "x"
  branches    = ["main", "dev"]
  cicd        = { enable = false }
}

run "domain_from_zone" {
  command = plan
  variables { dns_config = { set_dns_config = true, zone_name = "www-zone" } }
  assert {
    condition     = local.domain_name == "www.example.com"
    error_message = "Domain should come from the zone."
  }
  assert {
    condition     = google_certificate_manager_dns_authorization.default["dev"].domain == "dev.www.example.com"
    error_message = "Non-default branches should be served on a subdomain."
  }
}

run "domain_matching_zone" {
  command = plan
  variables { dns_config = { set_dns_config = true, zone_name = "www-zone", domain_name = "www.example.com" } }
}

run "domain_matching_zone_with_trailing_dot" {
  command = plan
  variables { dns_config = { set_dns_config = true, zone_name = "www-zone", domain_name = "www.example.com." } }
  assert {
    condition     = local.domain_name == "www.example.com"
    error_message = "Trailing dot should be trimmed."
  }
}

run "domain_not_matching_zone_rejected" {
  command = plan
  variables { dns_config = { set_dns_config = true, zone_name = "www-zone", domain_name = "docs.example.com" } }
  expect_failures = [data.google_dns_managed_zone.default_zone]
}

run "domain_without_zone" {
  command = plan
  variables { dns_config = { domain_name = "docs.example.com." } }
  assert {
    condition     = local.domain_name == "docs.example.com"
    error_message = "domain_name should be used, without the trailing dot."
  }
  assert {
    condition     = output.dns_auth_creds != null && length(google_dns_record_set.cert_auth) == 0
    error_message = "Without set_dns_config, records should be output instead of created."
  }
}

run "set_dns_config_without_zone_rejected" {
  command = plan
  variables { dns_config = { set_dns_config = true, domain_name = "example.com" } }
  expect_failures = [var.dns_config]
}

run "no_domain_or_zone_rejected" {
  command = plan
  variables { dns_config = {} }
  expect_failures = [var.dns_config]
}
