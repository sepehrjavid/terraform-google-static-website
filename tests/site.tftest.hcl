mock_provider "google" {
  mock_data "google_dns_managed_zone" {
    defaults = { dns_name = "example.com." }
  }
}
mock_provider "time" {}

variables {
  project_id  = "p"
  region      = "europe-north2"
  name_prefix = "x"
  branches    = ["main", "dev"]
  cicd        = { enable = false }
  dns_config  = { set_dns_config = true, zone_name = "example-com" }
}

run "www_off_by_default" {
  command = plan
  assert {
    condition     = !contains(keys(google_certificate_manager_dns_authorization.default), "www")
    error_message = "No www DNS authorization expected."
  }
  assert {
    condition     = !contains(google_certificate_manager_certificate.default.managed[0].domains, "www.example.com")
    error_message = "www.example.com should not be on the certificate."
  }
  assert {
    condition     = !anytrue([for r in google_compute_url_map.default.host_rule : contains(r.hosts, "www.example.com")])
    error_message = "No www host rule expected."
  }
  assert {
    condition     = length(google_compute_url_map.default.path_matcher) == 2
    error_message = "Only the branch path matchers expected."
  }
  assert {
    condition     = toset(keys(google_dns_record_set.website_dub_domanins)) == toset(["dev"]) && !contains(keys(google_dns_record_set.cert_auth), "www")
    error_message = "No www DNS records expected."
  }
}

run "www_redirect" {
  command = plan
  variables { enable_www_redirect = true }
  assert {
    condition = (
      google_certificate_manager_dns_authorization.default["www"].name == "x-www-dns-auth" &&
      google_certificate_manager_dns_authorization.default["www"].domain == "www.example.com"
    )
    error_message = "Unexpected www DNS authorization."
  }
  assert {
    condition = (
      toset(google_certificate_manager_certificate.default.managed[0].domains) == toset(["example.com", "dev.example.com", "www.example.com"]) &&
      length(google_certificate_manager_certificate.default.managed[0].dns_authorizations) == 3
    )
    error_message = "The certificate should cover www.example.com with its own DNS authorization."
  }
  assert {
    condition     = anytrue([for r in google_compute_url_map.default.host_rule : r.hosts == toset(["www.example.com"]) && r.path_matcher == "www-redirect"])
    error_message = "www.example.com should be routed to the redirect path matcher."
  }
  assert {
    condition = alltrue([
      for m in google_compute_url_map.default.path_matcher : (
        m.default_service == null &&
        length(m.path_rule) == 0 &&
        m.default_url_redirect[0].host_redirect == "example.com" &&
        m.default_url_redirect[0].https_redirect == null &&
        m.default_url_redirect[0].path_redirect == null &&
        m.default_url_redirect[0].strip_query == false &&
        m.default_url_redirect[0].redirect_response_code == "MOVED_PERMANENTLY_DEFAULT"
      ) if m.name == "www-redirect"
    ]) && length(google_compute_url_map.default.path_matcher) == 3
    error_message = "www-redirect should 301 to example.com, keeping the path and query."
  }
  assert {
    condition = (
      google_dns_record_set.website_dub_domanins["www"].name == "www.example.com." &&
      google_dns_record_set.website_dub_domanins["www"].type == "CNAME" &&
      toset(google_dns_record_set.website_dub_domanins["www"].rrdatas) == toset(["example.com."])
    )
    error_message = "Unexpected www CNAME."
  }
  assert {
    condition     = google_dns_record_set.cert_auth["www"].managed_zone == "example-com"
    error_message = "The www validation record should be created."
  }
  assert {
    condition     = output.dns_auth_creds == null
    error_message = "With set_dns_config, no records should be output."
  }
}

run "www_redirect_manual_dns" {
  command = plan
  variables {
    enable_www_redirect = true
    dns_config          = { domain_name = "example.com" }
  }
  assert {
    condition     = toset(keys(output.dns_auth_creds)) == toset(["main", "dev", "www"])
    error_message = "dns_auth_creds should include the www validation record."
  }
  assert {
    condition     = length(google_dns_record_set.website_dub_domanins) == 0 && length(google_dns_record_set.cert_auth) == 0
    error_message = "Without set_dns_config, no records should be created."
  }
}

run "www_branch_fine_without_www_redirect" {
  command = plan
  variables { branches = ["main", "www"] }
}

run "www_branch_rejected_with_www_redirect" {
  command = plan
  variables {
    branches            = ["main", "www"]
    enable_www_redirect = true
  }
  expect_failures = [var.enable_www_redirect]
}

run "www_default_branch_rejected_with_www_redirect" {
  command = plan
  variables {
    branches            = ["www"]
    default_branch_name = "www"
    enable_www_redirect = true
  }
  expect_failures = [var.enable_www_redirect]
}

run "not_found_page_defaults_to_index" {
  command = plan
  assert {
    condition = alltrue([
      for b in google_storage_bucket.website_bucket : b.website[0].main_page_suffix == "index.html" && b.website[0].not_found_page == "index.html"
    ])
    error_message = "Unknown paths should get index.html by default."
  }
}

run "not_found_page_passed_through" {
  command = plan
  variables { not_found_page = "404.html" }
  assert {
    condition = alltrue([
      for b in google_storage_bucket.website_bucket : b.website[0].main_page_suffix == "index.html" && b.website[0].not_found_page == "404.html"
    ])
    error_message = "not_found_page should be set on every bucket."
  }
}

run "empty_not_found_page_rejected" {
  command = plan
  variables { not_found_page = "" }
  expect_failures = [var.not_found_page]
}

run "not_found_page_with_leading_slash_rejected" {
  command = plan
  variables { not_found_page = "/404.html" }
  expect_failures = [var.not_found_page]
}
