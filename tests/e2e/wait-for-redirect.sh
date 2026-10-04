#!/usr/bin/env bash
# Usage: wait-for-redirect.sh URL LOCATION [HOST] [TIMEOUT_MINUTES]
# Polls URL until it answers with a 301 redirect to LOCATION. HOST sets the
# Host header, to reach a load balancer by its IP.
set -euo pipefail

url=$1
location=$2
host=${3:-}
deadline=$(($(date +%s) + ${4:-20} * 60))

args=(-sS --max-time 10 -o /dev/null -w '%{http_code} %{redirect_url}')
if [[ -n $host ]]; then
  args+=(-H "Host: $host")
fi

until [[ "$(curl "${args[@]}" "$url" 2>/dev/null)" == "301 $location" ]]; do
  if (($(date +%s) >= deadline)); then
    echo "Timed out waiting for $url (Host: ${host:-default}) to redirect to $location" >&2
    curl -sS -i --max-time 10 ${host:+-H "Host: $host"} "$url" >&2 || true
    exit 1
  fi
  sleep 15
done
echo "OK $url (Host: ${host:-default}) redirects to $location"
