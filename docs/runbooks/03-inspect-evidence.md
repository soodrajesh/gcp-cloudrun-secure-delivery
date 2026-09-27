# 03 · Inspect the evidence — "prove what's running in prod"

```bash
IMG=$(gcloud run services describe quote-prod --region $REGION --format='value(spec.template.spec.containers[0].image)')

# both attestations
for A in built-by-pipeline scan-passed; do
  gcloud container binauthz attestations list --attestor=$A --attestor-project=$PROJECT --artifact-url="$IMG"
done

# SBOM (stored by digest at build time)
gcloud storage cat gs://$(terraform -chdir=terraform output -raw work_bucket)/sbom/${IMG##*@sha256:}.cdx.json | python3 -m json.tool | head -30

# SLSA build provenance (Container Analysis; the CLI's --show-provenance flag is unreliable, see runbook 07)
TOK=$(gcloud auth print-access-token)
curl -s -H "Authorization: Bearer $TOK" \
  "https://containeranalysis.googleapis.com/v1/projects/$PROJECT/occurrences?filter=resourceUrl%3D%22https%3A%2F%2F$IMG%22%20AND%20kind%3D%22BUILD%22"
```
*Captured:* every image running in staging or prod has exactly one `built-by-pipeline` attestation, one `scan-passed` attestation, one BUILD provenance occurrence, and an SBOM at `gs://…/sbom/<digest>.cdx.json` with 100+ components.
