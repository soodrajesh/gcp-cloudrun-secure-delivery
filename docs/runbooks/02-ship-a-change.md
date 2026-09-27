# 02 · Ship a change

```bash
IMG=$(./scripts/build.sh)                 # test -> build -> SBOM -> gate -> push -> attest
REL=$(./scripts/release.sh "$IMG")        # release pinned to that digest -> staging (automatic)
gcloud deploy releases promote --release "$REL" --delivery-pipeline quote --region $REGION --to-target prod
# … review, then:
gcloud deploy rollouts approve $(gcloud deploy rollouts list --release "$REL" --delivery-pipeline quote --region $REGION --filter='targetId=prod' --format='value(name.basename())' | tail -1) --release "$REL" --delivery-pipeline quote --region $REGION
```
Prod then canaries 25 % → 50 % → 100 %, advancing automatically after a 60 s soak (watch with `gcloud deploy rollouts describe`, or `scripts/lib.sh`'s `wait_traffic`/`finish_prod`).

**Options:** `./scripts/build.sh --tag T` (default: timestamp) · `--error-rate N` (bake in an N % fault, for drills) · `--vuln-demo` (bake in a known CRITICAL CVE — the build should FAIL).
