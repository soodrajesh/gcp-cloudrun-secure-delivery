# ADR 0004 — Immutable tags; rollback is a normal, approved rollout

**Status:** accepted

Artifact Registry's `apps` repository has `docker_config.immutable_tags = true`: a tag can be created once and never re-pointed. Combined with digest-pinned releases ([ADR 0003](0003-digest-pinned-canary.md)), "what is running in prod" is never ambiguous, and a compromised build cannot quietly replace bits behind a tag already in use.

Rollback is **not** a special code path: `gcloud deploy targets rollback prod --release <previous-good>` creates a normal rollout of a previous release, which goes through the same approval and (if not already stable, the same canary) machinery as a forward release. Proven live in the bad-release drill ([runbook 05](../runbooks/05-release-and-rollback.md)): a faulty release is cancelled at canary-25 and the previous release is rolled back and approved like any other rollout.
