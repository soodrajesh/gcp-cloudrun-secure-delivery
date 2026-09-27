# Runbooks

Each runbook: **When** · **Commands** · **Output** · **If it goes wrong**.

> **Output status.** Blocks headed *Captured* are real output from the live deployment (2026-09-27). Nothing here is invented.

```bash
export PROJECT=$(gcloud config get-value project) REGION=europe-west1
```

| # | Runbook | Use it when |
|---|---|---|
| 01 | [Build & teardown](01-build-and-teardown.md) | Standing the pipeline up / down |
| 02 | [Ship a change](02-ship-a-change.md) | Building and releasing normally |
| 03 | [Inspect the evidence](03-inspect-evidence.md) | "Prove what's running in prod" |
| 04 | [Admission denials](04-admission-denials.md) | Binary Authorization blocked a deploy |
| 05 | [Release & rollback](05-release-and-rollback.md) | A bad release; rolling back |
| 06 | [Cost](06-cost.md) | Bill questions |
| 07 | [Troubleshooting](07-troubleshooting.md) | Problems already hit during development |
