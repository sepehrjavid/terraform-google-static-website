#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# lab2.sepehrjavid.com isn't delegated, so reach the load balancer by IP.
ip=$(terraform output -raw lb_ip)
../wait-for-redirect.sh "http://$ip/" https://lab2.sepehrjavid.com/ lab2.sepehrjavid.com
../wait-for-redirect.sh "http://$ip/" https://dev.lab2.sepehrjavid.com/ dev.lab2.sepehrjavid.com
