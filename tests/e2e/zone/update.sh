#!/usr/bin/env bash
# Turns the www redirect off on the running deployment. The certificate must be
# kept and the branches must keep serving.
set -euo pipefail
cd "$(dirname "$0")"

marker="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
plan=$(mktemp)

terraform plan -input=false -out="$plan" -var enable_www_redirect=false
if ! terraform show -json "$plan" | jq -e '
  .resource_changes[]
  | select(.address == "module.website.google_certificate_manager_certificate.default")
  | .change.actions == ["no-op"]' >/dev/null; then
  echo "Turning the www redirect off would change the certificate" >&2
  exit 1
fi
terraform apply -input=false "$plan"

../wait-for-url.sh https://lab.sepehrjavid.com/ "main $marker" 5
../wait-for-url.sh https://dev.lab.sepehrjavid.com/ "dev $marker" 5
