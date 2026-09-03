#!/usr/bin/env bash
# Brings up the local dev infra stack: Postgres, Redis, MinIO (+ bucket bootstrap). Also verifies
# the observability stack (Grafana/Loki/Tempo/Prometheus/OTel Collector) is up first, same
# ordering kart-devops used, so telemetry is never silently missing once ums-core exists.
#
# First run only: auto-copies .env.example -> .env (throwaway local Postgres/MinIO creds) - see
# .env.example's own header comment for why this is safe to do unprompted, unlike a real secret.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

if [[ ! -f .env ]]; then
  echo "No .env found - creating it from .env.example (default dev-only creds)."
  cp .env.example .env
fi

echo "Bringing up the observability stack (Grafana/Loki/Tempo/Prometheus/OTel Collector)..."
docker compose --env-file ports.env -f docker-compose.observability.yml up -d

echo
echo "Bringing up infra (Postgres/Redis/MinIO)..."
docker compose --env-file ports.env --env-file .env up -d

set -a
source ports.env
set +a

cat <<EOF

Stack starting. Useful next steps:
  scripts/dev-logs.sh              tail every container's logs together
  scripts/dev-logs.sh postgres     tail just one container
  docker compose ps                see container status

Once healthy:
  Postgres:        localhost:${POSTGRES_PORT}
  Redis:            localhost:${REDIS_PORT}
  MinIO API:        http://localhost:${MINIO_API_PORT}
  MinIO Console:     http://localhost:${MINIO_CONSOLE_PORT}
  Grafana:           http://localhost:${GRAFANA_PORT}  (admin / admin)
  Prometheus:        http://localhost:${PROMETHEUS_PORT}

scripts/dev-down.sh stops everything. See README.md for the full port table and how this relates
to ums-infra's kind/Helm cluster.
EOF
