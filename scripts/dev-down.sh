#!/usr/bin/env bash
# Stops the ENTIRE local UMS stack: all six ums-*-web frontends, ums-core + UMS.Workers, infra
# (Postgres/Redis/MinIO), and the observability stack -- the exact reverse of dev-up.sh.
# Pass -v to also wipe data volumes (Postgres/MinIO data) for a genuinely fresh start next time.
#
# Usage: scripts/dev-down.sh       stop and remove containers, keep data volumes
#        scripts/dev-down.sh -v    stop and remove containers AND data volumes

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
section() { echo; echo "${BOLD}${CYAN}==> $*${RESET}"; }
ok()      { echo "${GREEN}  ✓${RESET} $*"; }

WIPE_VOLUMES=false
if [[ "${1:-}" == "-v" ]]; then
  WIPE_VOLUMES=true
fi

section "Stopping application + infra stack (ums-*-web, ums-core, UMS.Workers, Postgres, Redis, MinIO)"
if $WIPE_VOLUMES; then
  docker compose --env-file ports.env --env-file .env down -v
  ok "stopped and removed containers + data volumes"
else
  docker compose --env-file ports.env --env-file .env down
  ok "stopped and removed containers (data volumes kept)"
fi

section "Stopping observability stack (Grafana, Loki, Tempo, Prometheus, OTel Collector)"
if $WIPE_VOLUMES; then
  docker compose --env-file ports.env -f docker-compose.observability.yml down -v
  ok "stopped and removed containers + data volumes"
else
  docker compose --env-file ports.env -f docker-compose.observability.yml down
  ok "stopped and removed containers (data volumes kept)"
fi

cat <<EOF

${BOLD}${GREEN}Everything stopped.${RESET}
${DIM}Run scripts/dev-up.sh any time to bring it all back up.$([ "$WIPE_VOLUMES" = false ] && echo " Data volumes were kept, so Postgres/MinIO data survives (pass -v next time to wipe it).")${RESET}
EOF
