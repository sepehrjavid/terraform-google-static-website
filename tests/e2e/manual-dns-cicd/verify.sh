#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if terraform state pull | grep -qF "${TF_VAR_github_token:?must be set}"; then
  echo "GitHub token found in Terraform state" >&2
  exit 1
fi
echo "OK GitHub token is not in the state"
