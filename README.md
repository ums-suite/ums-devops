# ums-devops

Reusable GitHub Actions workflows, local-dev infra (`docker-compose.yml`), and the shared
observability stack for every `ums-*` repo — `ums-core`, `UMS.Workers`, the six `ums-*-web` apps,
and `ums-design-system`/`ums-shared` all call these rather than hand-rolling their own pipelines
(per [`ums-conventions.md`](https://github.com/ums-suite/ums-platform/blob/main/docs/standards/ums-conventions.md)
— "CI: every repo calls the reusable workflow published from `ums-devops`"). Nothing here is
deployed — it's consumed by other repos' `.github/workflows/ci.yml` and by any developer's own
local dev-loop.

## Status

Infra/observability stack and reusable workflows are real and usable **now**, ahead of any
application repo existing — see the verification section below. Per-repo application wiring
(Dockerfiles, actual CI callers, `ums-core`/`UMS.Workers`/frontend service blocks in
`docker-compose.yml`) happens as each repo is scaffolded in later
[`release/DEVELOPMENT_PLAN.md`](https://github.com/ums-suite/ums-suite/blob/main/release/DEVELOPMENT_PLAN.md)
flows.

## Repository layout

| Path | Purpose |
|---|---|
| `.github/workflows/dotnet-module-ci.yml` | Reusable .NET 10 CI: format, build, vulnerable-package scan (§11.1), test, optional Docker build + Trivy scan. |
| `.github/workflows/angular-app-ci.yml` | Reusable Angular 22 CI: `npm audit` (§11.1), ESLint/Prettier/Stylelint, headless-Chrome tests, build, optional Docker build + Trivy scan. |
| `.github/workflows/docker-build-push.yml` | Builds, Trivy-scans, and (default-branch only) pushes a repo's image to `ghcr.io`. |
| `.github/workflows/openapi-client-codegen.yml` | Regenerates `ums-shared`'s TypeScript client from `ums-core`'s single OpenAPI contract; fails on drift. |
| `docker-compose.yml` | Local dev infra: Postgres, Redis, MinIO (+ bucket bootstrap). |
| `docker-compose.observability.yml` | Local dev Grafana + Loki + Tempo + Prometheus + OTel Collector. |
| `observability/` | Config for the above: collector pipeline, Prometheus scrape config, Tempo config, Grafana datasource/dashboard provisioning. |
| `scripts/` | `dev-up.sh` / `dev-down.sh` / `dev-logs.sh` — bring the stacks up/down/tail. |
| `ports.env` | Canonical host port registry (committed, not a secret). |
| `.env.example` | Throwaway local Postgres/MinIO credentials — copy to gitignored `.env`. |

## Why this is simpler than a typical microservices `devops` repo

UMS is **one backend deployable** (`ums-core`, ADR-0001) + **one background worker**
(`UMS.Workers`, ADR-0014) + **six independent Angular frontends** — not a fleet of N
microservices. That collapses several things a larger platform's devops repo would need:

- **No per-service `global.json`/shared-secrets-file system.** With one backend deployable there's
  no "which of 13 services does this secret belong to" problem to solve — a plain gitignored
  `.env` (ums-conventions.md's own pattern: "Local development reads from a gitignored `.env` ...
  the cluster reads from Kubernetes Secrets") is enough.
- **One shared Postgres *instance*, and ADR-0004 means one shared *database* too** — schema-per-
  module (`identity`, `academic`, `admission`, ...), not database-per-service. `ums-core`'s own EF
  Core migrations create that schema layout; this repo's `docker-compose.yml` only provisions the
  bare Postgres instance, no per-schema bootstrap SQL.
- **No API gateway repo, no gateway routing config here.** `ums-core`'s own ASP.NET Core pipeline
  does module routing, auth, and rate-limiting in-process (`container-diagram.md`, "Why One API
  Container, Not a Gateway"). `ums-infra`'s ingress-nginx is the only routing layer this repo's
  stack needs to assume exists.
- **No message broker.** The outbox pattern (ADR-0014) is DB-table-based, polled by `UMS.Workers`
  — no RabbitMQ/Kafka to stand up, configure, or scan.

## Quickstart

```bash
scripts/dev-up.sh              # copies .env.example -> .env on first run, brings up observability then infra
scripts/dev-logs.sh            # tail postgres/redis/minio logs together (or dev-logs.sh <name> for one)
scripts/dev-logs.sh --observability   # tail Grafana/Loki/Tempo/Prometheus/OTel Collector instead
scripts/dev-down.sh            # stop everything (-v also wipes data volumes)
```

## What's here today (`docker-compose.yml`)

Postgres, Redis, and MinIO (S3-compatible object storage, ADR-0010) — the three data/cache/storage
containers `container-diagram.md` names — on one Docker network, one command.

**Excluded on purpose:** `ums-core`, `UMS.Workers`, and all six `ums-*-web` frontends have no code
yet (every repo but `ums-infra`/`ums-devops` is "Not Started" in `release/DEVELOPMENT_PLAN.md`) —
add a service block for each here once that repo is actually scaffolded, mirroring how
`kart-devops`'s own `docker-compose.yml` originally excluded its own not-yet-scaffolded stub
services with the same reasoning ("no code yet — add them here once they're actually scaffolded").

## Ports

[`ports.env`](ports.env) is the single source of truth for every host port below — committed (not
a secret), read via `docker compose --env-file ports.env`. `scripts/dev-up.sh`/`dev-down.sh`/
`dev-logs.sh` already pass it; run `docker compose --env-file ports.env --env-file .env <command>`
yourself if calling `docker compose` directly.

| What | Host port |
|---|---|
| Postgres | 5433 |
| Redis | 6380 |
| MinIO API | 9000 |
| MinIO Console | 9001 |
| Grafana | 3000 |
| Loki | 3100 |
| Tempo | 3200 |
| Prometheus | 9090 |
| OTel Collector (gRPC / HTTP) | 4317 / 4318 |
| OTel Collector (Prometheus exporter) | 8889 |
| OTel Collector (health check) | 13133 |

**Reserved, not yet wired to any container** (documented now so the choice is made once, not
improvised per-repo later — see `ports.env`'s own comment):

| Repo | Host port |
|---|---|
| `ums-core` (single API, no gateway) | 8080 |
| `UMS.Workers` (health endpoints only) | 8081 |
| `ums-public-web` | 4200 |
| `ums-admission-web` | 4201 |
| `ums-student-web` | 4202 |
| `ums-faculty-web` | 4203 |
| `ums-admin-web` | 4204 |
| `ums-alumni-web` | 4205 |

## Credentials

Postgres and MinIO bootstrap credentials come from `.env` (gitignored) — see
[`.env.example`](.env.example) for the shape and defaults. `scripts/dev-up.sh` auto-copies the
example on first run since these are throwaway, local-only-reachable dev credentials, not real
secrets.

## Workflows

### `.github/workflows/dotnet-module-ci.yml`

Reusable CI for `ums-core` and `UMS.Workers` (.NET 10). Covers `ums-conventions.md`'s Code
Quality section (`dotnet format --verify-no-changes`; NetAnalyzers/StyleCop.Analyzers run as part
of `dotnet build` via the calling repo's own analyzer package references and
`Directory.Build.props`'s `TreatWarningsAsErrors`) plus `ums-requirements.md` §11.1's two scan
gates: `dotnet list package --vulnerable --include-transitive` (dependency scan) and an optional
Trivy image scan (container scan), both fail-the-build on any finding.

```yaml
jobs:
  ci:
    uses: ums-suite/ums-devops/.github/workflows/dotnet-module-ci.yml@main
    with:
      solution-path: UmsCore.sln
      image-name: ums-core
```

| Input | Required | Default | Description |
|---|---|---|---|
| `dotnet-version` | no | `10.0.x` | .NET SDK version to install. |
| `solution-path` | yes | — | Path to the repo's `.sln` file, relative to the repo root. |
| `run-docker-build` | no | `true` | Also build the repo's `Dockerfile` and Trivy-scan the image. |
| `image-name` | no | `""` | Image tag used for the Trivy scan. Required when `run-docker-build` is true. |

### `.github/workflows/angular-app-ci.yml`

Reusable CI for any Angular 22 repo (the six `ums-*-web` apps, `ums-design-system`). Assumes the
calling repo's `package.json` defines `lint`, `format:check`, `stylelint`, `test`, `build` scripts
per `ums-conventions.md`'s Frontend Code Quality section (ESLint `@angular-eslint` +
typescript-eslint strict, `--max-warnings 0`; Prettier; Stylelint). Adds `npm audit
--audit-level=high` (§11.1 dependency scan) and an optional Trivy image scan (§11.1 container
scan).

```yaml
jobs:
  ci:
    uses: ums-suite/ums-devops/.github/workflows/angular-app-ci.yml@main
    with:
      image-name: ums-student-web
```

| Input | Required | Default | Description |
|---|---|---|---|
| `node-version` | no | `22.x` | Node.js version to install. |
| `working-directory` | no | `.` | Directory containing the app's `package.json`. |
| `run-docker-build` | no | `true` | Also build the repo's `Dockerfile` and Trivy-scan the image. |
| `image-name` | no | `""` | Image tag used for the Trivy scan. Required when `run-docker-build` is true. |

### `.github/workflows/docker-build-push.yml`

Builds a calling repo's `Dockerfile`, Trivy-scans the image, and — only on a push to the default
branch, and only once the scan has passed — pushes it to `ghcr.io` tagged `:latest` and
`:<git-sha>`. This is the concrete implementation of §11.1's "container image scanning ... on
every build; a critical/high finding blocks merge": the scan runs on every build (PR included),
and a vulnerable image is never published regardless of branch.

| Input | Required | Default | Description |
|---|---|---|---|
| `image-name` | yes | — | Image name, without registry/owner prefix, e.g. `ums-core`. |
| `dockerfile-path` | no | `Dockerfile` | Path to the Dockerfile, relative to the repo root. |
| `context` | no | `.` | Docker build context, relative to the repo root. |

### `.github/workflows/openapi-client-codegen.yml`

Called from `ums-shared`'s own CI: regenerates its TypeScript client from `ums-core`'s **single**
OpenAPI contract (one source, not per-service like a microservices platform) via
`openapi-generator-cli`, then fails the build on an uncommitted regeneration diff.

| Input | Required | Default | Description |
|---|---|---|---|
| `source-repo` | no | `ums-suite/ums-core` | `owner/repo` that owns the OpenAPI contract. |
| `source-ref` | no | `main` | Git ref of `source-repo` to check out. |
| `contract-path` | yes | — | Path to the contract file within `source-repo`. |
| `output-dir` | yes | — | Where the generated client lands in the calling (`ums-shared`) repo. |
| `npm-name` | no | `""` | `npmName` generator property. |
| `generator-image-tag` | no | `v7.9.0` | Pinned `openapitools/openapi-generator-cli` image tag. |
| `fail-on-diff` | no | `true` | Fail on an uncommitted regeneration diff. |

Optional secret: `source-checkout-token` — a token with read access to `ums-core`, for cross-repo
checkout if it's private (falls back to the default `GITHUB_TOKEN` otherwise).

### `docker-compose.observability.yml`

The shared local-dev Grafana + Loki + Tempo + Prometheus (+ OpenTelemetry Collector) stack
(`ums-conventions.md` Observability section). Owned once, centrally, here — every repo's own
README should point developers at this file rather than copy-pasting one. See
[`observability/grafana/provisioning/dashboards/json/README.md`](observability/grafana/provisioning/dashboards/json/README.md)
for why there are no real dashboards committed yet.

## Verification performed

- Every workflow YAML parses (`python3 -c "import yaml; yaml.safe_load(open(...))"`); `actionlint`
  was not available in this environment to lint the Actions-specific schema beyond that.
- `docker compose -f docker-compose.yml up -d` (with `ports.env`/`.env`) — Postgres, Redis, and
  MinIO all reached `healthy`; `minio-init` exited 0 having created the bootstrap bucket. Torn down
  with `docker compose down -v`.
- `docker compose -f docker-compose.observability.yml up -d` — Grafana, Loki, Tempo, Prometheus,
  and the OTel Collector all reached `Running`/healthy. Torn down the same way.
- `helm`/`terraform`/`kind` are not installed in this environment — nothing here depends on them,
  but see `ums-infra/README.md` for what those tools would additionally verify there.

## What's not here yet

Terraform/Helm/K8s cluster bootstrap is `ums-infra`'s job, not this repo's. A shared
`.editorconfig`/analyzer ruleset consumed by multiple repos is a natural next addition here once
`ums-core` exists to confirm what's actually shared. `ums-core`/`UMS.Workers`/frontend service
blocks in `docker-compose.yml`, and each repo's own `.github/workflows/ci.yml` caller, are added as
each repo is scaffolded (`release/DEVELOPMENT_PLAN.md`).
