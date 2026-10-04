# Plan-only checks against the real lab.sepehrjavid.com zone; nothing is
# created. Run from the repo root with:
#   terraform test -test-directory=tests/e2e/faulty-inputs
# project_id and region come from TF_VAR_project_id and TF_VAR_region.

variables {
  name_prefix = "e2efaulty"
  branches    = ["main"]
  cicd        = { enable = false }
}

run "domain_not_matching_zone_rejected" {
  command = plan
  variables {
    dns_config = {
      set_dns_config = true
      zone_name      = "lab-sepehrjavid-com"
      domain_name    = "lab2.sepehrjavid.com"
    }
  }
  expect_failures = [data.google_dns_managed_zone.default_zone]
}

run "domain_matching_zone_with_trailing_dot" {
  command = plan
  variables {
    dns_config = {
      set_dns_config = true
      zone_name      = "lab-sepehrjavid-com"
      domain_name    = "lab.sepehrjavid.com."
    }
  }
}
