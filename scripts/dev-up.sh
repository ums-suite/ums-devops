#!/usr/bin/env bash
# Brings up the ENTIRE local UMS stack in one command: observability (Grafana/Loki/Tempo/
# Prometheus/OTel Collector), infra (Postgres/Redis/MinIO), the backend (ums-core UMS.Host +
# UMS.Workers), and all six ums-*-web frontends -- every container-diagram.md container, on one
# Docker network. Prints live progress as each layer comes up, then a full URL/status summary at
# the end so it's obvious what's running and where to look.
#
# First run only: auto-copies .env.example -> .env (throwaway local Postgres/MinIO creds) - see
# .env.example's own header comment for why this is safe to do unprompted, unlike a real secret.
#
# Usage: scripts/dev-up.sh          (uses cached images if source hasn't changed)
#        scripts/dev-up.sh --build  (forces a full rebuild of ums-core/UMS.Workers/every frontend)

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

BUILD_FLAG=""
if [[ "${1:-}" == "--build" ]]; then
  BUILD_FLAG="--build"
fi

# ---------- tiny logging helpers (plain ANSI, no external deps) ----------
BOLD=$'\033[1m'; DIM=$'\033[2m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; CYAN=$'\033[36m'; RESET=$'\033[0m'
section() { echo; echo "${BOLD}${CYAN}==> $*${RESET}"; }
ok()      { echo "${GREEN}  ✓${RESET} $*"; }
warn()    { echo "${YELLOW}  !${RESET} $*"; }
fail()    { echo "${RED}  ✗${RESET} $*"; }
info()    { echo "${DIM}  $*${RESET}"; }

START_TIME=$(date +%s)

section "Step 1/5 -- credentials"
if [[ ! -f .env ]]; then
  info "No .env found - creating it from .env.example (default dev-only creds)."
  cp .env.example .env
  ok ".env created"
else
  ok ".env already present"
fi

section "Step 2/5 -- observability stack (Grafana, Loki, Tempo, Prometheus, OTel Collector)"
docker compose --env-file ports.env -f docker-compose.observability.yml up -d
ok "observability containers started"

section "Step 3/5 -- infra + backend + all six frontends"
info "This builds ums-core, UMS.Workers, and every ums-*-web image if their source changed"
info "(first run, or after --build, this can take several minutes - .NET restore/publish and six Angular builds)"
docker compose --env-file ports.env --env-file .env up -d $BUILD_FLAG
ok "all application containers started"

set -a
source ports.env
set +a

section "Step 4/5 -- waiting for health checks"
# Services with a real HEALTHCHECK in docker-compose.yml. Poll docker's own health status rather
# than guessing at a fixed sleep - prints a live line per service as each one flips healthy so the
# terminal shows real progress instead of going silent for a minute.
HEALTH_SERVICES=(postgres redis minio ums-core ums-workers ums-public-web ums-admission-web ums-student-web ums-faculty-web ums-admin-web ums-alumni-web)
TIMEOUT_SECONDS=180
DEADLINE=$(( $(date +%s) + TIMEOUT_SECONDS ))
declare -A REPORTED

while true; do
  ALL_DONE=true
  for svc in "${HEALTH_SERVICES[@]}"; do
    cid=$(docker compose --env-file ports.env --env-file .env ps -q "$svc" 2>/dev/null || true)
    if [[ -z "$cid" ]]; then
      ALL_DONE=false
      continue
    fi
    status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}}' "$cid" 2>/dev/null || echo "unknown")
    if [[ "$status" == "healthy" || "$status" == "no-healthcheck" ]]; then
      if [[ -z "${REPORTED[$svc]:-}" ]]; then
        ok "$svc is up"
        REPORTED[$svc]=1
      fi
    else
      ALL_DONE=false
    fi
  done

  if $ALL_DONE; then
    break
  fi
  if [[ $(date +%s) -ge $DEADLINE ]]; then
    warn "Timed out after ${TIMEOUT_SECONDS}s waiting for every service to report healthy."
    warn "This doesn't necessarily mean something is wrong - check status yourself:"
    info "  docker compose --env-file ports.env --env-file .env ps"
    info "  scripts/dev-logs.sh <service-name>"
    break
  fi
  sleep 2
done

section "Step 5/5 -- current container status"
docker compose --env-file ports.env --env-file .env ps

ELAPSED=$(( $(date +%s) - START_TIME ))

cat <<EOF

${BOLD}${GREEN}Stack is up (${ELAPSED}s).${RESET}

${BOLD}Frontend apps (open these in your browser):${RESET}
  Public website        http://localhost:${PUBLIC_WEB_PORT}
  Admission portal       http://localhost:${ADMISSION_WEB_PORT}
  Student portal         http://localhost:${STUDENT_WEB_PORT}
  Faculty portal         http://localhost:${FACULTY_WEB_PORT}
  Admin console          http://localhost:${ADMIN_WEB_PORT}
  Alumni portal          http://localhost:${ALUMNI_WEB_PORT}

${BOLD}Backend:${RESET}
  ums-core API           http://localhost:${UMS_CORE_PORT}            (OpenAPI doc: /openapi/v1.json)
  ums-core health        http://localhost:${UMS_CORE_PORT}/health/live
  UMS.Workers health     http://localhost:${UMS_WORKERS_PORT}/health/live

${BOLD}Infra:${RESET}
  Postgres               localhost:${POSTGRES_PORT}
  Redis                  localhost:${REDIS_PORT}
  MinIO API              http://localhost:${MINIO_API_PORT}
  MinIO Console          http://localhost:${MINIO_CONSOLE_PORT}   (login: value of MINIO_ROOT_USER/PASSWORD in .env)

${BOLD}Observability:${RESET}
  Grafana                http://localhost:${GRAFANA_PORT}   (admin / admin)
  Prometheus             http://localhost:${PROMETHEUS_PORT}

${BOLD}Useful next steps:${RESET}
  scripts/dev-logs.sh                 tail every application container's logs together
  scripts/dev-logs.sh ums-core        tail just one container (any service name from 'docker compose ps')
  scripts/dev-logs.sh --observability tail the Grafana/Loki/Tempo/Prometheus/OTel stack instead
  docker compose --env-file ports.env --env-file .env ps    see container status any time
  scripts/dev-down.sh                 stop everything

${DIM}Known limitation: ums-public-web/ums-admission-web/ums-alumni-web server-render some pages
inside their own container using a host-only API URL, so a data-heavy page's very first byte can
show a degraded empty state before your browser's own JS fetches the real data client-side
(which works fine). This self-corrects almost instantly and is a documented trade-off, not a bug.${RESET}
EOF
