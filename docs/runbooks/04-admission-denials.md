# 04 · Admission denials

**When:** `gcloud run deploy` (or a Cloud Deploy rollout) fails with *"is not authorized by policy"*.

1. **Read which attestor is missing** — the error names it:
```
denied by attestor projects/<p>/attestors/scan-passed: No attestations found that were valid and signed by a key trusted by the attestor
```
`scan-passed` missing → the image was never gated (built outside this pipeline, or the `gate` step was skipped/failed and someone pushed it another way — pushing is normally gate-gated so this should be rare). `built-by-pipeline` missing → not built by Cloud Build with this repo's build SA at all.
2. **Confirm, don't guess:**
```bash
for A in built-by-pipeline scan-passed; do
  gcloud container binauthz attestations list --attestor=$A --attestor-project=$PROJECT --artifact-url="<repo>/quote@sha256:..."
done
```
3. **Fix:** rebuild through `./scripts/build.sh` (never `docker push` directly), or if this is a legitimate exception, add a scoped entry to `admission_whitelist_patterns` in `terraform/supplychain.tf` — reviewed, not routine.
4. **Audit trail:** every allow/deny is in Cloud Audit Logs (`protoPayload.methodName:"google.cloud.binaryauthorization"`).

*Captured live:* an image with no attestation, one attested `built-by-pipeline` only, and one attested `scan-passed` only were each denied, naming the missing attestor each time; the pipeline's own image was admitted.
