#!/usr/bin/env bash
# Fails if the test project has anything left besides its permanent setup:
# the lab.sepehrjavid.com zone (NS/SOA only), the e2e state bucket and the
# default compute service account. A failed listing also fails the check.
set -euo pipefail

project=${TF_VAR_project_id:?must be set}
region=${TF_VAR_region:?must be set}
state_bucket=${E2E_STATE_BUCKET:-}
leftovers=$(mktemp)

list() { # LABEL COMMAND...
  local label=$1
  shift
  "$@" --project "$project" --format='value(name)' | sed "s|^|$label |" >>"$leftovers"
}

list "forwarding rule" gcloud compute forwarding-rules list --global
list "https proxy" gcloud compute target-https-proxies list
list "http proxy" gcloud compute target-http-proxies list
list "url map" gcloud compute url-maps list
list "backend bucket" gcloud compute backend-buckets list
list "global address" gcloud compute addresses list --global
list "certificate map" gcloud certificate-manager maps list
list "certificate" gcloud certificate-manager certificates list
list "dns authorization" gcloud certificate-manager dns-authorizations list
list "secret" gcloud secrets list
list "build trigger" gcloud builds triggers list --region "$region"
list "build connection" gcloud builds connections list --region "$region"
list "bucket" gcloud storage buckets list
list "service account" gcloud iam service-accounts list
gcloud dns record-sets list --zone lab-sepehrjavid-com --project "$project" --format='value(name,type)' |
  sed 's/^/dns record /' >>"$leftovers"
gcloud projects get-iam-policy "$project" --format=json |
  jq -r '.bindings[] | select(.role == "roles/logging.logWriter") | .members[] | "log writer grant \(.)"' >>"$leftovers"

# Drop the permanent setup.
grep -vE "^(bucket $state_bucket|service account .*-compute@developer\.gserviceaccount\.com|dns record lab\.sepehrjavid\.com\.\s+(NS|SOA))$" \
  "$leftovers" >"$leftovers.unexpected" || true

if [[ -s $leftovers.unexpected ]]; then
  echo "Resources left in $project:" >&2
  cat "$leftovers.unexpected" >&2
  exit 1
fi
echo "OK $project is clean"
