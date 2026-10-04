mock_provider "google" {}
mock_provider "time" {}

variables {
  project_id  = "p"
  region      = "europe-north2"
  name_prefix = "mysite"
  dns_config  = { domain_name = "example.com" }
  cicd = {
    repo_uri      = "https://github.com/a/b.git"
    github_config = { app_installation_id = "1", access_token = "tok" }
  }
}

run "build_sa_ids_are_short" {
  command = plan
  variables { branches = ["main", "staging"] }
  assert {
    condition     = google_service_account.website_build_sa["staging"].account_id == "mysite-staging-build"
    error_message = "Unexpected build SA ID."
  }
}

run "build_sa_id_of_30_chars_fits" {
  command = plan
  variables { branches = ["main", "release-candidate"] } # mysite-release-candidate-build
}

run "build_sa_id_of_31_chars_rejected" {
  command = plan
  variables { branches = ["main", "release-candidates"] }
  expect_failures = [var.cicd]
}

run "long_names_fine_with_own_build_sas" {
  command = plan
  variables {
    branches = ["main", "release-candidates"]
    cicd = {
      repo_uri      = "https://github.com/a/b.git"
      github_config = { app_installation_id = "1", access_token = "tok" }
      build_sa_ids = {
        main               = "projects/p/serviceAccounts/a@p.iam.gserviceaccount.com"
        release-candidates = "projects/p/serviceAccounts/b@p.iam.gserviceaccount.com"
      }
    }
  }
}

run "long_names_fine_without_cicd" {
  command = plan
  variables {
    branches = ["main", "release-candidates"]
    cicd     = { enable = false }
  }
}

run "bucket_name_over_63_chars_rejected" {
  command = plan
  variables {
    branches = ["main", "a-very-long-branch-name-that-goes-on-and-on-x"]
    cicd     = { enable = false }
  }
  expect_failures = [var.branches]
}

run "slash_rejected" {
  command = plan
  variables { branches = ["main", "feature/login"] }
  expect_failures = [var.branches]
}

run "uppercase_rejected" {
  command = plan
  variables { branches = ["main", "Dev"] }
  expect_failures = [var.branches]
}

run "underscore_rejected" {
  command = plan
  variables { branches = ["main", "my_branch"] }
  expect_failures = [var.branches]
}

run "leading_digit_rejected" {
  command = plan
  variables { branches = ["main", "2024-release"] }
  expect_failures = [var.branches]
}

run "trailing_hyphen_rejected" {
  command = plan
  variables { branches = ["main", "dev-"] }
  expect_failures = [var.branches]
}

run "default_branch_must_be_in_branches" {
  command = plan
  variables { branches = ["master", "dev"] }
  expect_failures = [var.default_branch_name]
}

run "default_branch_can_be_overridden" {
  command = plan
  variables {
    branches            = ["master", "dev"]
    default_branch_name = "master"
  }
}
