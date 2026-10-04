#!/usr/bin/env bash
# Usage: wait-for-url.sh URL TEXT [TIMEOUT_MINUTES]
# Polls URL until the response body contains TEXT. The first check of a new
# deployment also waits for the managed certificate to be issued.
set -euo pipefail

url=$1
text=$2
deadline=$(($(date +%s) + ${3:-60} * 60))

until curl -fsS --max-time 10 "$url" 2>/dev/null | grep -qF "$text"; do
  if (($(date +%s) >= deadline)); then
    echo "Timed out waiting for $url to contain \"$text\"" >&2
    curl -sS -i --max-time 10 "$url" >&2 || true
    exit 1
  fi
  sleep 30
done
echo "OK $url"
