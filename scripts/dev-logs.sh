#!/usr/bin/env bash
# Tails logs for the infra stack, or a single container if named (e.g. dev-logs.sh postgres).
# Pass --observability to tail the Grafana/Loki/Tempo/Prometheus/OTel Collector stack instead.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ "${1:-}" == "--observability" ]]; then
  shift
  docker compose --env-file ports.env -f docker-compose.observability.yml logs -f --tail=200 "$@"
else
  docker compose --env-file ports.env --env-file .env logs -f --tail=200 "$@"
fi
