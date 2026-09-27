# 05 · Release & rollback — the bad-release drill

```bash
./scripts/demo-bad-release.sh
```
Runs live: builds a version that fails 60 % of requests (it passes the vulnerability gate — it is a *logic* bug, not a vulnerability), releases it, promotes and approves to prod, samples real traffic at canary-25, then rolls back.

*Captured (this build):*
| Step | Result |
|---|---|
| Baseline (before) | 30/30 requests 200, 0 errors |
| Canary 25 % sampled (100 req) | 72 old version, 10 new (faulty), **18 errors** — contained to roughly a quarter of traffic |
| Rollback | `gcloud deploy targets rollback prod --release <previous>`, approved, rollout `SUCCEEDED` |
| After (60 req) | 100 % old version, 0 errors |

**Manual rollback** (if you don't want the full drill):
```bash
gcloud deploy rollouts cancel <bad-rollout> --release <bad-release> --delivery-pipeline quote --region $REGION
gcloud deploy targets rollback prod --delivery-pipeline quote --region $REGION --release <previous-good-release>
# then approve the resulting rollout, same as any other
```
The 5xx-ratio alert (`docs/adr`, `terraform/monitoring.tf`) fires on the same signal a human would use to decide to roll back: > 5 % 5xx on `quote-prod` for 2 minutes.
