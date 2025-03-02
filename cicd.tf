locals {
  gh_token_secret_version_id = try(var.cicd.github_config.existing_token_secret_version_id, null)
  github_access_token        = try(sensitive(var.cicd.github_config.access_token), null)
  create_gh_connection       = var.cicd.enable && var.cicd.existing_gh_conn_name == null
  create_secret              = local.create_gh_connection && local.gh_token_secret_version_id == null
}

resource "google_project_service" "project" {
  for_each = var.cicd.enable ? toset(["secretmanager.googleapis.com", "cloudbuild.googleapis.com"]) : []
  service  = each.value

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_on_destroy = false
}

resource "time_sleep" "wait_30_seconds" {
  depends_on = [google_project_service.project]

  create_duration = "30s"
}

resource "google_secret_manager_secret" "github_token_secret" {
  count     = local.create_secret ? 1 : 0
  secret_id = "github_access_token"

  replication {
    auto {}
  }

  depends_on = [time_sleep.wait_30_seconds]
}

resource "google_secret_manager_secret_version" "github_token_secret_version" {
  count       = local.create_secret ? 1 : 0
  secret      = google_secret_manager_secret.github_token_secret[0].id
  secret_data = local.github_access_token
}

data "google_iam_policy" "serviceagent_secretAccessor" {
  count = local.create_secret ? 1 : 0

  binding {
    role    = "roles/secretmanager.secretAccessor"
    members = ["serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"]
  }
}

resource "google_secret_manager_secret_iam_policy" "policy" {
  count       = local.create_secret ? 1 : 0
  project     = google_secret_manager_secret.github_token_secret[0].project
  secret_id   = google_secret_manager_secret.github_token_secret[0].secret_id
  policy_data = data.google_iam_policy.serviceagent_secretAccessor[0].policy_data
}

resource "google_cloudbuildv2_connection" "git_connection" {
  count    = local.create_gh_connection ? 1 : 0
  location = data.google_client_config.client_config.region
  name     = "gh-connection"

  github_config {
    app_installation_id = var.cicd.github_config.app_installation_id
    authorizer_credential {
      oauth_token_secret_version = coalesce(
        local.gh_token_secret_version_id,
        try(google_secret_manager_secret_version.github_token_secret_version[0].id, null)
      )
    }
  }
  depends_on = [google_secret_manager_secret_iam_policy.policy]
}

resource "google_cloudbuildv2_repository" "git_repository" {
  count             = var.cicd.enable ? 1 : 0
  location          = data.google_client_config.client_config.region
  name              = "${var.name_prefix}-website-repo"
  parent_connection = coalesce(var.cicd.existing_gh_conn_name, google_cloudbuildv2_connection.git_connection[0].name)
  remote_uri        = var.cicd.github_config.repo_uri
}

resource "google_service_account" "website_build_sa" {
  for_each     = var.cicd.enable ? var.branches : []
  account_id   = "${var.name_prefix}-${each.key}-website-build-sa"
  display_name = "website Cloud Build SA"
}

resource "google_project_iam_member" "website_log_writer" {
  for_each = var.cicd.enable ? google_service_account.website_build_sa : {}
  project  = data.google_client_config.client_config.project
  role     = "roles/logging.logWriter"
  member   = "serviceAccount:${google_service_account.website_build_sa[each.key].email}"
}

resource "google_storage_bucket_iam_member" "build_sa_write_access" {
  for_each = var.cicd.enable ? var.branches : []
  bucket   = google_storage_bucket.website_bucket[each.key].name
  role     = "roles/storage.legacyBucketWriter"
  member   = "serviceAccount:${google_service_account.website_build_sa[each.key].email}"
}

resource "google_cloudbuild_trigger" "git_trigger" {
  for_each        = var.cicd.enable ? var.branches : []
  name            = "${var.name_prefix}-${each.value}"
  location        = data.google_client_config.client_config.region
  service_account = google_service_account.website_build_sa[each.key].id
  filename        = "cloudbuild.yaml"

  repository_event_config {
    repository = google_cloudbuildv2_repository.git_repository[0].id

    push {
      branch = each.value
    }
  }
}
