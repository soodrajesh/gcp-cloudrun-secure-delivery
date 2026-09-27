# 06 · Cost

| Item | While running |
|---|---|
| Cloud Run ×2 (`quote-staging`, `quote-prod`), scale-to-zero | €0 idle; pennies per burst |
| Cloud Build (test, build, scan, attest — a few minutes per build) | cents per build |
| Cloud KMS (2 asymmetric keys, sign operations) | cents |
| Artifact Registry, Cloud Storage (SBOMs, build sources) | cents |
| Cloud Deploy | free (no per-rollout charge at this scale) |

A full build-test-teardown cycle (several builds, releases, a canary drill) costs well under €1. A budget (€10 default) alerts at 50 %/100 %. After `down.sh` the cost is €0 — except the KMS key ring, which Google never lets you delete (it schedules key material for destruction but keeps the ring name reserved).
