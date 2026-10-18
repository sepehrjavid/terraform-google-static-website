#!/usr/bin/env bash
# Usage: wait-for-not-found.sh URL TEXT [TIMEOUT_MINUTES]
# Polls URL until it answers with status 404 and a body containing TEXT.
set -euo pipefail

url=$1
text=$2
deadline=$(($(date +%s) + ${3:-20} * 60))
body=$(mktemp)

not_found() {
  local status
  status=$(curl -sS --max-time 10 -o "$body" -w '%{http_code}' "$url" 2>/dev/null) || true
  [[ $status == 404 ]] && grep -qF "$text" "$body"
}

until not_found; do
  if (($(date +%s) >= deadline)); then
    echo "Timed out waiting for $url to answer 404 with \"$text\"" >&2
    curl -sS -i --max-time 10 "$url" >&2 || true
    exit 1
  fi
  sleep 15
done
echo "OK $url answers 404 with \"$text\""
