mock_provider "google" {}
mock_provider "time" {}

variables {
  project_id  = "p"
  region      = "europe-north2"
  name_prefix = "x"
  branches    = ["main"]
  cicd        = { enable = false }
  dns_config  = { domain_name = "example.com" }
}

run "extra_backend_matches_bare_prefix" {
  command = plan
  variables {
    lb = { extra_backends = { main = { url_prefix = "api", backend_id = "projects/p/global/backendServices/api" } } }
  }
  assert {
    condition = alltrue([
      anytrue([for r in one(google_compute_url_map.default.path_matcher).path_rule : toset(r.paths) == toset(["/api", "/api/*"]) && r.service == "projects/p/global/backendServices/api"]),
      anytrue([for r in one(google_compute_url_map.default.path_matcher).path_rule : toset(r.paths) == toset(["/*"])]),
    ])
    error_message = "Unexpected path rules."
  }
}

run "http_redirect_can_be_disabled" {
  command = plan
  variables { enable_http_redirect = false }
  assert {
    condition     = length(google_compute_global_forwarding_rule.http_forwarding_rule) == 0
    error_message = "No HTTP listener expected."
  }
}
