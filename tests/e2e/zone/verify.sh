#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

marker="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
tmp=$(mktemp -d)

upload() { # BUCKET OBJECT TEXT
  echo "$3 $marker" >"$tmp/$2"
  gcloud storage cp "$tmp/$2" "gs://$1/$2"
}

upload "$(terraform output -json buckets | jq -r .main)" index.html main
upload "$(terraform output -json buckets | jq -r .dev)" index.html dev
upload "$(terraform output -raw api_bucket)" index.html api
upload "$(terraform output -raw api_bucket)" ping.txt ping

../wait-for-url.sh https://lab.sepehrjavid.com/ "main $marker"
../wait-for-url.sh https://dev.lab.sepehrjavid.com/ "dev $marker"
../wait-for-url.sh https://lab.sepehrjavid.com/api "api $marker"
../wait-for-url.sh https://lab.sepehrjavid.com/api/ping.txt "ping $marker"

../wait-for-redirect.sh http://lab.sepehrjavid.com/ https://lab.sepehrjavid.com/
