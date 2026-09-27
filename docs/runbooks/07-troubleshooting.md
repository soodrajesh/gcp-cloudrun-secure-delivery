# 07 · Troubleshooting — problems actually hit while building this

| # | Symptom | Cause | Fix |
|---|---|---|---|
| D1 | Trivy: `FATAL … --skip-db-update cannot be specified on the first run` | Each Cloud Build step is a fresh container; the SBOM step's downloaded vulnerability DB is gone by the time the gate step starts | Merge SBOM + gate into one step so they share the container (and the DB download) |
| D2 | Cloud Deploy prod rollout stuck: `canary-25`/`canary-50` SKIPPED, `stable` PENDING, forever | First deployment to an empty target has no previous revision to canary against; Cloud Deploy waits for a manual `rollouts advance` | `scripts/lib.sh`'s `finish_prod` detects `SKIPPED SKIPPED PENDING` and advances automatically |
| D3 | `advance-canary` automation runs all `FAILED`: `permission_denied … clouddeploy.rollouts.advance` | `roles/clouddeploy.jobRunner` (execution-time only) does not include `rollouts.advance` | Grant `roles/clouddeploy.releaser` to the deploy service account too |
| D4 | `gcloud deploy targets describe` / `delivery-pipelines describe` → `--format='value(x)'` returns nothing even though the field exists | These `describe` commands wrap the resource in extra top-level keys (`Target`, `Delivery Pipeline`, `Active Pipeline`, …) that vary by command | Use `--format=json` and parse in Python, or `list` (not `describe`), which is unwrapped |
| D5 | `gcloud artifacts docker images describe --show-provenance --format=json` never shows provenance | The flag/format combination doesn't reliably surface it via this CLI path | Query the Container Analysis REST API directly for `kind="BUILD"` occurrences ([runbook 03](03-inspect-evidence.md)) |
| D6 | `gcloud artifacts docker tags add` → 404 | The destination tag argument was empty (an upstream variable that should have held a tag name was empty) — a downstream symptom of D4 | Fix the root cause; the tags-add syntax itself was correct |
| D7 | `--exit-code 1 --skip-db-update` on the FIRST scan of the day always fails | See D1 — same root issue, different flag | (fixed by D1) |
