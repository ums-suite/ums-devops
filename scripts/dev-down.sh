#!/usr/bin/env bash
# Stops the local dev infra + observability stacks. Pass -v to also wipe data volumes (fresh
# start next time).

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ "${1:-}" == "-v" ]]; then
  docker compose --env-file ports.env --env-file .env down -v
  docker compose --env-file ports.env -f docker-compose.observability.yml down -v
else
  docker compose --env-file ports.env --env-file .env down
  docker compose --env-file ports.env -f docker-compose.observability.yml down
fi
