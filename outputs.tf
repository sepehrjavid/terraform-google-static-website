output "lb_ip" {
  value       = google_compute_global_address.default.address
  description = "IP address to reach the website"
}

output "dns_auth_creds" {
  value = var.dns_config.set_dns_config ? null : {
    for key, auth in google_certificate_manager_dns_authorization.default :
    key => {
      cname  = auth.dns_resource_record[0].name
      type   = auth.dns_resource_record[0].type
      secret = auth.dns_resource_record[0].data
    }
  }
}

output "github_connection_name" {
  value = var.cicd.enable ? coalesce(var.cicd.existing_gh_conn_name, try(google_cloudbuildv2_connection.git_connection[0].name, null)) : null
}

output "buckets" {
  value = { for k in var.branches : k => google_storage_bucket.website_bucket[k].name }
}

output "build_sa" {
  value = var.cicd.enable && var.cicd.build_sa_ids == null ? google_service_account.website_build_sa : {}
}