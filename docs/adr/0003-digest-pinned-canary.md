# ADR 0003 — Deploy by digest; Cloud Deploy owns the canary, not hand-rolled traffic splitting

**Status:** accepted

`gcloud deploy releases create` is given `--images quote=<repo>/quote@sha256:...`, never a tag. Cloud Run's own traffic-splitting is driven by Cloud Deploy's canary strategy (25 % → 50 % → 100 %, advancing automatically after a soak via a `google_clouddeploy_automation`), so a release is reproducible from its digest and the rollout state machine (phases, approval, rollback) is Google's, not a bash script's.

**A real permission gap found here:** the automation's identity (`csd-deploy`) needs `clouddeploy.rollouts.advance` to move a rollout from `canary-25` to `canary-50` on its own. `roles/clouddeploy.jobRunner` (execution only) does not include it; `roles/clouddeploy.releaser` does. The first live run showed three `advance-canary` automation runs failing with `permission_denied` before this was caught (see [runbook 08](../runbooks/08-troubleshooting.md)).

**Trade-off:** a first deployment to an empty target has no previous revision to canary against, so Cloud Deploy **skips** both canary phases and waits at `stable` for a manual `rollouts advance`. `scripts/lib.sh`'s `finish_prod` detects this and advances automatically; it is not a bug in later releases, which do split traffic.
