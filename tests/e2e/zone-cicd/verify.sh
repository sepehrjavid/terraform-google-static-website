#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if terraform state pull | grep -qF "${TF_VAR_github_token:?must be set}"; then
  echo "GitHub token found in Terraform state" >&2
  exit 1
fi
echo "OK GitHub token is not in the state"

marker="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
page="$(mktemp -d)/index.html"
echo "e2e $marker" >"$page"
gcloud storage cp "$page" "gs://$(terraform output -json buckets | jq -r .e2e)/index.html"

../wait-for-url.sh https://lab.sepehrjavid.com/ "e2e $marker"

# HTTP redirect is off, so nothing should answer on port 80.
if curl -sS --max-time 10 -o /dev/null http://lab.sepehrjavid.com/ 2>/dev/null; then
  echo "Expected no HTTP listener with enable_http_redirect = false" >&2
  exit 1
fi
echo "OK no HTTP listener"
