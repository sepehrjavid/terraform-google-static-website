locals {
  gh_token_secret_version_id = try(var.cicd.github_config.existing_token_secret_version_id, null)
  github_access_token        = try(sensitive(var.cicd.github_config.access_token), null)
  create_gh_connection       = var.cicd.enable && var.cicd.existing_gh_conn_name == null
  create_secret              = local.create_gh_connection && try(var.cicd.github_config.access_token, null) != null
  secret_version_id_regex    = "^projects/([^/]+)/secrets/([^/]+)/versions/[^/]+$"
  grant_cdn_invalidation     = var.cicd.enable && var.enable_cdn

  # Keyed by branch, not email: build SAs passed in may only be known after
  # apply, and for_each keys must be known at plan time.
  build_sa_emails = var.cicd.enable ? {
    for b in var.branches : b => var.cicd.build_sa_ids == null ? google_service_account.website_build_sa[b].email : regex("^projects/[^/]+/serviceAccounts/([^/]+)$", var.cicd.build_sa_ids[b])[0]
  } : {}
}

resource "google_project_service" "project" {
  for_each = var.cicd.enable ? toset(["secretmanager.googleapis.com", "cloudbuild.googleapis.com"]) : []
  project  = var.project_id
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
  project   = var.project_id
  secret_id = "${var.name_prefix}-github-access-token"

  replication {
    auto {}
  }

  depends_on = [time_sleep.wait_30_seconds]
}

resource "google_secret_manager_secret_version" "github_token_secret_version" {
  count                  = local.create_secret ? 1 : 0
  secret                 = google_secret_manager_secret.github_token_secret[0].id
  secret_data_wo         = local.github_access_token
  secret_data_wo_version = var.cicd.github_config.access_token_version
}

resource "google_secret_manager_secret_iam_member" "cloudbuild_token_accessor" {
  count     = local.create_gh_connection ? 1 : 0
  project   = local.create_secret ? google_secret_manager_secret.github_token_secret[0].project : regex(local.secret_version_id_regex, local.gh_token_secret_version_id)[0]
  secret_id = local.create_secret ? google_secret_manager_secret.github_token_secret[0].secret_id : regex(local.secret_version_id_regex, local.gh_token_secret_version_id)[1]
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-cloudbuild.iam.gserviceaccount.com"

  # The Cloud Build service agent only exists once the API is enabled.
  depends_on = [time_sleep.wait_30_seconds]
}

resource "google_cloudbuildv2_connection" "git_connection" {
  count    = local.create_gh_connection ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = "${var.name_prefix}-gh-connection"

  github_config {
    app_installation_id = var.cicd.github_config.app_installation_id
    authorizer_credential {
      oauth_token_secret_version = coalesce(
        local.gh_token_secret_version_id,
        try(google_secret_manager_secret_version.github_token_secret_version[0].id, null)
      )
    }
  }
  depends_on = [
    time_sleep.wait_30_seconds,
    google_secret_manager_secret_iam_member.cloudbuild_token_accessor,
  ]
}

resource "google_cloudbuildv2_repository" "git_repository" {
  count             = var.cicd.enable ? 1 : 0
  project           = var.project_id
  location          = var.region
  name              = "${var.name_prefix}-website-repo"
  parent_connection = coalesce(var.cicd.existing_gh_conn_name, try(google_cloudbuildv2_connection.git_connection[0].name, null))
  remote_uri        = var.cicd.repo_uri
}

resource "google_service_account" "website_build_sa" {
  for_each     = var.cicd.enable && var.cicd.build_sa_ids == null ? var.branches : []
  project      = var.project_id
  account_id   = "${var.name_prefix}-${each.key}-build"
  display_name = "website Cloud Build SA"
}

resource "google_project_iam_member" "website_log_writer" {
  for_each = local.build_sa_emails
  project  = var.project_id
  role     = "roles/logging.logWriter"
  member   = "serviceAccount:${each.value}"
}

resource "google_storage_bucket_iam_member" "build_sa_write_access" {
  for_each = local.build_sa_emails
  bucket   = google_storage_bucket.website_bucket[each.key].name
  role     = "roles/storage.objectUser"
  member   = "serviceAccount:${each.value}"
}

# A deleted custom role's ID can't be reused for up to 44 days (Terraform can
# only undelete the role during the first 7), so every new role gets its
# creation time as a suffix. Otherwise destroy and apply with the same
# name_prefix could fail.
resource "time_static" "cdn_invalidator_role" {
  count = local.grant_cdn_invalidation ? 1 : 0

  triggers = {
    project_id  = var.project_id
    name_prefix = var.name_prefix
  }
}

resource "google_project_iam_custom_role" "cdn_invalidator" {
  count       = local.grant_cdn_invalidation ? 1 : 0
  project     = var.project_id
  role_id     = "${replace(var.name_prefix, "-", "_")}_cdn_invalidator_${time_static.cdn_invalidator_role[0].unix}"
  title       = "${var.name_prefix} CDN cache invalidator"
  description = "Lets the website build service accounts invalidate the Cloud CDN cache."
  permissions = ["compute.urlMaps.invalidateCache"]
}

# URL maps don't have IAM policies of their own, so the role is granted on the
# project.
resource "google_project_iam_member" "build_sa_cdn_invalidator" {
  for_each = local.grant_cdn_invalidation ? local.build_sa_emails : {}
  project  = var.project_id
  role     = google_project_iam_custom_role.cdn_invalidator[0].id
  member   = "serviceAccount:${each.value}"
}

resource "google_cloudbuild_trigger" "git_trigger" {
  for_each        = var.cicd.enable ? var.branches : []
  project         = var.project_id
  name            = "${var.name_prefix}-${each.value}"
  location        = var.region
  service_account = try(var.cicd.build_sa_ids[each.key], google_service_account.website_build_sa[each.key].id)
  filename        = var.cicd.build_config_filename

  substitutions = {
    _WEBSITE_BUCKET  = google_storage_bucket.website_bucket[each.key].name
    _WEBSITE_URL_MAP = google_compute_url_map.default.name
    _WEBSITE_DOMAIN  = local.domains[each.key]
  }

  repository_event_config {
    repository = google_cloudbuildv2_repository.git_repository[0].id

    push {
      branch = "^${each.value}$"
    }
  }
}
