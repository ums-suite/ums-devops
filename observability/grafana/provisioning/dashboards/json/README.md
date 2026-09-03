# Provisioned dashboards

Empty on purpose. Any `*.json` dashboard file dropped in this directory loads automatically on
Grafana startup (provider config: `../dashboards.yaml`) and stays in sync every ~30s.

**No real dashboards exist yet** because no service emits metrics/logs/traces until `ums-core`
(release/DEVELOPMENT_PLAN.md Flow #2) exists — this stack's Grafana/Loki/Tempo/Prometheus/OTel
Collector are wired up and verified working (see the root `README.md`'s verification section),
but there is nothing upstream generating telemetry yet. Add dashboards here once `ums-core`
exposes real metrics.

## Exporting a dashboard you built in the UI

1. Open the dashboard in Grafana -> dashboard settings (gear icon) -> JSON Model, or use the
   share/export panel's "Export as JSON" option.
2. In the exported JSON, remove the top-level `"id"` field (or set it to `null`) so Grafana treats
   it as a new provisioned dashboard rather than trying to match an internal DB id that won't
   exist on a fresh volume.
3. Save the file here, e.g. `ums-core-overview.json`.
4. Commit it. It loads automatically the next time any Grafana container starts from this repo —
   your machine, a teammate's, or CI.

`allowUiUpdates: true` in `../dashboards.yaml` means editing a provisioned dashboard in the UI
afterwards is fine day-to-day — it just won't survive a volume wipe until you re-export and commit
the updated JSON.
