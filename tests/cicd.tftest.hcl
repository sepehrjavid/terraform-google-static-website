mock_provider "google" {
  mock_data "google_project" {
    defaults = { number = "123456" }
  }
}
mock_provider "time" {}

variables {
  project_id  = "p"
  region      = "europe-north2"
  name_prefix = "x"
  branches    = ["main"]
  dns_config  = { domain_name = "example.com" }
}

run "new_token_secret" {
  command = plan
  variables {
    cicd = {
      repo_uri      = "https://github.com/a/b.git"
      github_config = { app_installation_id = "1", access_token = "tok" }
    }
  }
  assert {
    condition     = google_secret_manager_secret_iam_member.cloudbuild_token_accessor[0].secret_id == "x-github-access-token"
    error_message = "Service agent should get access to the created secret."
  }
  assert {
    condition     = google_secret_manager_secret_version.github_token_secret_version[0].secret_data == null
    error_message = "The token must only be passed write-only."
  }
  assert {
    condition     = tostring(google_secret_manager_secret_version.github_token_secret_version[0].secret_data_wo_version) == "1"
    error_message = "access_token_version should default to 1."
  }
}

run "token_version_bump" {
  command = plan
  variables {
    cicd = {
      repo_uri      = "https://github.com/a/b.git"
      github_config = { app_installation_id = "1", access_token = "tok", access_token_version = 2 }
    }
  }
  assert {
    condition     = tostring(google_secret_manager_secret_version.github_token_secret_version[0].secret_data_wo_version) == "2"
    error_message = "access_token_version not passed through."
  }
}

run "existing_token_secret" {
  command = plan
  variables {
    cicd = {
      repo_uri = "https://github.com/a/b.git"
      github_config = {
        app_installation_id              = "1"
        existing_token_secret_version_id = "projects/other-proj/secrets/my-token/versions/3"
      }
    }
  }
  assert {
    condition     = length(google_secret_manager_secret.github_token_secret) == 0
    error_message = "No secret should be created."
  }
  assert {
    condition = (
      google_secret_manager_secret_iam_member.cloudbuild_token_accessor[0].project == "other-proj" &&
      google_secret_manager_secret_iam_member.cloudbuild_token_accessor[0].secret_id == "my-token" &&
      google_secret_manager_secret_iam_member.cloudbuild_token_accessor[0].member == "serviceAccount:service-123456@gcp-sa-cloudbuild.iam.gserviceaccount.com"
    )
    error_message = "Service agent should get access to the existing secret."
  }
}

run "existing_connection" {
  command = plan
  variables {
    cicd = { repo_uri = "https://github.com/a/b.git", existing_gh_conn_name = "c" }
  }
  assert {
    condition     = length(google_cloudbuildv2_connection.git_connection) == 0 && length(google_secret_manager_secret_iam_member.cloudbuild_token_accessor) == 0
    error_message = "No connection or secret access expected."
  }
}

run "branch_trigger_is_anchored" {
  command = plan
  variables {
    cicd = { repo_uri = "https://github.com/a/b.git", existing_gh_conn_name = "c" }
  }
  assert {
    condition     = google_cloudbuild_trigger.git_trigger["main"].repository_event_config[0].push[0].branch == "^main$"
    error_message = "Trigger should only match the exact branch."
  }
}

run "missing_repo_uri_rejected" {
  command = plan
  variables {
    cicd = { github_config = { app_installation_id = "1", access_token = "tok" } }
  }
  expect_failures = [var.cicd]
}

run "missing_connection_config_rejected" {
  command = plan
  variables {
    cicd = { repo_uri = "https://github.com/a/b.git" }
  }
  expect_failures = [var.cicd]
}

run "missing_token_rejected" {
  command = plan
  variables {
    cicd = {
      repo_uri      = "https://github.com/a/b.git"
      github_config = { app_installation_id = "1" }
    }
  }
  expect_failures = [var.cicd]
}

run "both_token_inputs_rejected" {
  command = plan
  variables {
    cicd = {
      repo_uri = "https://github.com/a/b.git"
      github_config = {
        app_installation_id              = "1"
        access_token                     = "tok"
        existing_token_secret_version_id = "projects/p/secrets/s/versions/1"
      }
    }
  }
  expect_failures = [var.cicd]
}

run "malformed_secret_version_id_rejected" {
  command = plan
  variables {
    cicd = {
      repo_uri      = "https://github.com/a/b.git"
      github_config = { app_installation_id = "1", existing_token_secret_version_id = "my-token" }
    }
  }
  expect_failures = [var.cicd]
}

run "build_sa_ids_missing_a_branch_rejected" {
  command = plan
  variables {
    branches = ["main", "dev"]
    cicd = {
      repo_uri              = "https://github.com/a/b.git"
      existing_gh_conn_name = "c"
      build_sa_ids          = { main = "projects/p/serviceAccounts/a@p.iam.gserviceaccount.com" }
    }
  }
  expect_failures = [var.cicd]
}
