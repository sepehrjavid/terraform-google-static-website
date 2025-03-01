###########################
##   Certificate Setup   ##
###########################

resource "google_project_service" "cert_manager_api" {
  service = "certificatemanager.googleapis.com"

  timeouts {
    create = "30m"
    update = "40m"
  }

  disable_on_destroy         = true
  disable_dependent_services = true
}

resource "time_sleep" "wait_30_seconds_cert" {
  depends_on = [google_project_service.cert_manager_api]

  create_duration = "30s"
}

resource "google_certificate_manager_dns_authorization" "default" {
  for_each   = var.branches
  name       = "${var.name_prefix}-${each.key}-dns-auth"
  domain     = each.key == var.default_branch_name ? local.domain_name : "${each.key}.${local.domain_name}"
  depends_on = [time_sleep.wait_30_seconds_cert]
}

resource "google_certificate_manager_certificate" "default" {
  name = "${var.name_prefix}-website-cert"

  managed {
    domains            = [for auth in google_certificate_manager_dns_authorization.default : auth.domain]
    dns_authorizations = [for auth in google_certificate_manager_dns_authorization.default : auth.id]
  }
}

resource "google_certificate_manager_certificate_map" "default" {
  name       = "${var.name_prefix}-website-cert-map"
  depends_on = [time_sleep.wait_30_seconds_cert]
}

resource "google_certificate_manager_certificate_map_entry" "default" {
  name         = "${var.name_prefix}-cert-map-entry"
  matcher      = "PRIMARY"
  map          = google_certificate_manager_certificate_map.default.name
  certificates = [google_certificate_manager_certificate.default.id]
}

#####################
##  Network Setup  ##
#####################

resource "google_compute_global_address" "default" {
  name = "${var.name_prefix}-website-ip"
}

resource "google_compute_backend_bucket" "backends" {
  for_each    = var.branches
  name        = "${var.name_prefix}-${each.key}-backend"
  bucket_name = google_storage_bucket.website_bucket[each.key].name
  enable_cdn  = var.enable_cdn
}

resource "google_compute_url_map" "default" {
  name = "${var.name_prefix}-https-lb"

  default_service = google_compute_backend_bucket.backends[var.default_branch_name].id

  dynamic "host_rule" {
    for_each = var.branches
    content {
      hosts        = [host_rule.value == var.default_branch_name ? local.domain_name : "${host_rule.value}.${local.domain_name}"]
      path_matcher = "${host_rule.value}-matcher"
    }
  }

  dynamic "path_matcher" {
    for_each = var.branches
    content {
      name            = "${path_matcher.value}-matcher"
      default_service = google_compute_backend_bucket.backends[path_matcher.value].id

      path_rule {
        paths   = ["/*"]
        service = google_compute_backend_bucket.backends[path_matcher.value].id
      }
    }
  }
}

resource "google_compute_target_https_proxy" "default" {
  name            = "${var.name_prefix}-https-lb-proxy"
  url_map         = google_compute_url_map.default.id
  certificate_map = "//certificatemanager.googleapis.com/${google_certificate_manager_certificate_map.default.id}"
}

resource "google_compute_global_forwarding_rule" "default" {
  name                  = "${var.name_prefix}-https-lb-forwarding-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "443"
  target                = google_compute_target_https_proxy.default.id
  ip_address            = google_compute_global_address.default.id
}

##############################
##    Redirect Resources    ##
##############################

resource "google_compute_url_map" "http_redirect_url_map" {
  count = var.enable_http_redirect ? 1 : 0
  name  = "${var.name_prefix}-http-redirect-lb"

  default_url_redirect {
    https_redirect         = true
    strip_query            = false
    redirect_response_code = "MOVED_PERMANENTLY_DEFAULT"
  }
}

resource "google_compute_target_http_proxy" "http_redirect_proxy" {
  count   = var.enable_http_redirect ? 1 : 0
  name    = "${var.name_prefix}-https-redirect-proxy"
  url_map = google_compute_url_map.http_redirect_url_map[0].id
}

resource "google_compute_global_forwarding_rule" "http_forwarding_rule" {
  count                 = var.enable_http_redirect ? 1 : 0
  name                  = "${var.name_prefix}-http-redirect-forwarding-rule"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  target                = google_compute_target_http_proxy.http_redirect_proxy[0].id
  port_range            = "80"
  ip_protocol           = "TCP"
  ip_address            = google_compute_global_address.default.address
}
