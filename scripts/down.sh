#!/usr/bin/env bash
# Delete everything this repo created, end to end.
#   ./scripts/down.sh            destroy everything (keeps the tiny shared Terraform state bucket)
#   ./scripts/down.sh --purge    also delete this repo's Terraform state (and the bucket if now empty)
# Cloud Run services are created by Cloud Deploy (outside Terraform), so they and the pipeline's
# releases are removed first. The project's Binary Authorization policy reverts to allow-all on destroy.
source "$(dirname "$0")/lib.sh"
need gcloud; need terraform
PURGE=0; [ "${1:-}" = "--purge" ] && PURGE=1

log "Project $PROJECT_ID — destroying everything managed by this repo"
tf_init
log "1/3 Cloud Run services and Cloud Deploy releases (created outside Terraform)"
for svc in quote-staging quote-prod rogue; do
  gcloud run services delete "$svc" --region "$REGION" --project "$PROJECT_ID" --quiet >/dev/null 2>&1 || true
done
gcloud deploy delivery-pipelines delete "$PIPELINE" --force --region "$REGION" --project "$PROJECT_ID" --quiet >/dev/null 2>&1 || true
ok "services and pipeline releases removed"

log "2/3 Terraform destroy"
$TF destroy -input=false -auto-approve
ok "destroyed"
rm -f "$ROOT/.last-image" "$ROOT/.last-release"; rm -rf "$ROOT/.test-tmp"

if [ "$PURGE" = 1 ]; then
  log "3/3 Purging this repo's Terraform state"
  gcloud storage rm -r "gs://$STATE_BUCKET/cloudrun-delivery/" --quiet >/dev/null 2>&1 || true
  if [ -z "$(gcloud storage ls "gs://$STATE_BUCKET/" 2>/dev/null)" ]; then
    gcloud storage rm -r "gs://$STATE_BUCKET" --quiet >/dev/null 2>&1 || true; ok "state prefix and (now empty) bucket removed"
  else ok "state prefix removed; bucket kept because other stacks still use it"; fi
else log "3/3 Kept state bucket gs://$STATE_BUCKET (a few KB; --purge removes it)"; fi

log "Anything billable left?"
echo "  Cloud Run (quote-*):         $(gcloud run services list --project "$PROJECT_ID" --format='value(name)' 2>/dev/null | grep -cE '^(quote-staging|quote-prod|rogue)$' || true)"
echo "  Cloud Deploy pipelines:      $(gcloud deploy delivery-pipelines list --region "$REGION" --project "$PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
echo "  Artifact Registry 'apps':    $(gcloud artifacts repositories list --location "$REGION" --project "$PROJECT_ID" --format='value(name)' 2>/dev/null | grep -c '/apps$' || true)"
echo "  Binary Auth attestors:       $(gcloud container binauthz attestors list --project "$PROJECT_ID" --format='value(name)' 2>/dev/null | wc -l | tr -d ' ')"
log "DONE"
