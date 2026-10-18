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

run "trigger_passes_website_substitutions" {
  command = plan
  variables {
    branches = ["main", "dev"]
    cicd     = { repo_uri = "https://github.com/a/b.git", existing_gh_conn_name = "c" }
  }
  assert {
    condition = alltrue([for b, domain in { main = "example.com", dev = "dev.example.com" } : google_cloudbuild_trigger.git_trigger[b].substitutions == tomap({
      _WEBSITE_BUCKET  = "x-${b}-website-bucket"
      _WEBSITE_URL_MAP = "x-https-lb"
      _WEBSITE_DOMAIN  = domain
    })])
    error_message = "Each trigger should pass its branch's bucket and domain, and the URL map name."
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

run "cdn_invalidator_role" {
  command = plan
  variables {
    name_prefix = "my-site"
    cicd        = { repo_uri = "https://github.com/a/b.git", existing_gh_conn_name = "c" }
  }
  override_resource {
    target          = time_static.cdn_invalidator_role
    override_during = plan
    values          = { unix = 1760720000 }
  }
  assert {
    condition     = google_project_iam_custom_role.cdn_invalidator[0].role_id == "my_site_cdn_invalidator_1760720000"
    error_message = "Role ID should be name_prefix with underscores for hyphens, plus the creation time."
  }
  assert {
    condition     = can(regex("^[a-zA-Z0-9_.]{3,64}$", google_project_iam_custom_role.cdn_invalidator[0].role_id))
    error_message = "Role ID doesn't match the format IAM accepts."
  }
  assert {
    condition     = google_project_iam_custom_role.cdn_invalidator[0].permissions == toset(["compute.urlMaps.invalidateCache"])
    error_message = "The role should only allow invalidating the CDN cache."
  }
}

run "cdn_invalidator_role_id_fits_longest_name_prefix" {
  command = plan
  variables {
    # The longest name_prefix the build SA ID check allows (<name_prefix>-m-build is 30 characters).
    name_prefix         = "a-twenty-two-char-pref"
    branches            = ["m"]
    default_branch_name = "m"
    cicd                = { repo_uri = "https://github.com/a/b.git", existing_gh_conn_name = "c" }
  }
  override_resource {
    target          = time_static.cdn_invalidator_role
    override_during = plan
    values          = { unix = 9999999999 }
  }
  assert {
    condition = (
      length(google_project_iam_custom_role.cdn_invalidator[0].role_id) == 49 &&
      can(regex("^[a-zA-Z0-9_.]{3,64}$", google_project_iam_custom_role.cdn_invalidator[0].role_id))
    )
    error_message = "Role ID should stay within IAM's 64 characters."
  }
}

run "cdn_invalidator_granted_to_each_build_sa" {
  command = plan
  variables {
    branches = ["main", "dev"]
    cicd     = { repo_uri = "https://github.com/a/b.git", existing_gh_conn_name = "c" }
  }
  override_resource {
    target          = google_project_iam_custom_role.cdn_invalidator
    override_during = plan
    values          = { id = "projects/p/roles/x_cdn_invalidator_0a1b2c3d" }
  }
  override_resource {
    target          = google_service_account.website_build_sa["main"]
    override_during = plan
    values          = { email = "x-main-build@p.iam.gserviceaccount.com" }
  }
  override_resource {
    target          = google_service_account.website_build_sa["dev"]
    override_during = plan
    values          = { email = "x-dev-build@p.iam.gserviceaccount.com" }
  }
  assert {
    condition     = length(google_project_iam_custom_role.cdn_invalidator) == 1
    error_message = "All branches should share one role."
  }
  assert {
    condition = (
      length(google_project_iam_member.build_sa_cdn_invalidator) == 2 &&
      google_project_iam_member.build_sa_cdn_invalidator["main"].member == "serviceAccount:x-main-build@p.iam.gserviceaccount.com" &&
      google_project_iam_member.build_sa_cdn_invalidator["dev"].member == "serviceAccount:x-dev-build@p.iam.gserviceaccount.com"
    )
    error_message = "Each branch's build SA should get the role."
  }
  assert {
    condition     = alltrue([for g in google_project_iam_member.build_sa_cdn_invalidator : g.project == "p" && g.role == "projects/p/roles/x_cdn_invalidator_0a1b2c3d"])
    error_message = "The custom role should be granted on the project."
  }
}

run "no_cdn_invalidator_without_cdn" {
  command = plan
  variables {
    enable_cdn = false
    cicd       = { repo_uri = "https://github.com/a/b.git", existing_gh_conn_name = "c" }
  }
  assert {
    condition     = length(google_project_iam_custom_role.cdn_invalidator) == 0 && length(google_project_iam_member.build_sa_cdn_invalidator) == 0
    error_message = "Nothing to invalidate without CDN."
  }
}

run "own_build_sas_get_the_same_roles" {
  command = plan
  variables {
    branches = ["main", "dev"]
    cicd = {
      repo_uri              = "https://github.com/a/b.git"
      existing_gh_conn_name = "c"
      build_sa_ids = {
        main = "projects/other/serviceAccounts/deploy-main@other.iam.gserviceaccount.com"
        dev  = "projects/other/serviceAccounts/deploy-dev@other.iam.gserviceaccount.com"
      }
    }
  }
  assert {
    condition     = length(google_service_account.website_build_sa) == 0
    error_message = "No build SAs should be created when they're passed in."
  }
  assert {
    condition = alltrue([for b in ["main", "dev"] : (
      google_storage_bucket_iam_member.build_sa_write_access[b].bucket == "x-${b}-website-bucket" &&
      google_storage_bucket_iam_member.build_sa_write_access[b].member == "serviceAccount:deploy-${b}@other.iam.gserviceaccount.com" &&
      google_project_iam_member.website_log_writer[b].member == "serviceAccount:deploy-${b}@other.iam.gserviceaccount.com" &&
      google_project_iam_member.build_sa_cdn_invalidator[b].member == "serviceAccount:deploy-${b}@other.iam.gserviceaccount.com"
    )])
    error_message = "Build SAs passed in should get write access to their bucket, the log writer role and the CDN invalidation role."
  }
  assert {
    condition     = length(google_project_iam_custom_role.cdn_invalidator) == 1
    error_message = "The CDN invalidation role should be created for build SAs passed in."
  }
}

run "build_sa_ids_wrong_format_rejected" {
  command = plan
  variables {
    cicd = {
      repo_uri              = "https://github.com/a/b.git"
      existing_gh_conn_name = "c"
      build_sa_ids          = { main = "deploy@other.iam.gserviceaccount.com" }
    }
  }
  expect_failures = [var.cicd]
}

run "build_sa_ids_with_account_id_rejected" {
  command = plan
  variables {
    cicd = {
      repo_uri              = "https://github.com/a/b.git"
      existing_gh_conn_name = "c"
      build_sa_ids          = { main = "projects/other/serviceAccounts/deploy" }
    }
  }
  expect_failures = [var.cicd]
}

run "shared_build_sa_rejected" {
  command = plan
  variables {
    branches = ["main", "dev"]
    cicd = {
      repo_uri              = "https://github.com/a/b.git"
      existing_gh_conn_name = "c"
      build_sa_ids = {
        main = "projects/other/serviceAccounts/deploy@other.iam.gserviceaccount.com"
        dev  = "projects/other/serviceAccounts/deploy@other.iam.gserviceaccount.com"
      }
    }
  }
  expect_failures = [var.cicd]
}

run "shared_build_sa_with_another_project_form_rejected" {
  command = plan
  variables {
    branches = ["main", "dev"]
    cicd = {
      repo_uri              = "https://github.com/a/b.git"
      existing_gh_conn_name = "c"
      build_sa_ids = {
        main = "projects/other/serviceAccounts/deploy@other.iam.gserviceaccount.com"
        dev  = "projects/-/serviceAccounts/deploy@other.iam.gserviceaccount.com"
      }
    }
  }
  expect_failures = [var.cicd]
}

run "no_cdn_invalidator_without_cicd" {
  command = plan
  variables {
    cicd = { enable = false }
  }
  assert {
    condition     = length(google_project_iam_custom_role.cdn_invalidator) == 0 && length(google_project_iam_member.build_sa_cdn_invalidator) == 0
    error_message = "No build SAs to grant the role to without CI/CD."
  }
}

run "url_map_name_output" {
  command = plan
  variables {
    name_prefix = "my-site"
    cicd        = { enable = false }
  }
  assert {
    condition     = output.url_map_name == "my-site-https-lb"
    error_message = "Unexpected URL map name."
  }
}
