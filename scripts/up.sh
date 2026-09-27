#!/usr/bin/env bash
# Build the whole secure-delivery system end to end, run a first release through every stage, then prove it:
#   state bucket -> infra (registry, KMS attestors, Binary Authorization policy, Cloud Deploy, alerts)
#   -> secure build (test, SBOM, vuln gate, push, 2 attestations) -> staging -> approve -> prod canary 25/50/100 -> live tests.
# Idempotent. `--plan` shows the Terraform plan and stops. `--skip-tests` skips the final test suite.
source "$(dirname "$0")/lib.sh"
PLAN_ONLY=0; SKIP_TESTS=0
for a in "$@"; do case "$a" in --plan) PLAN_ONLY=1;; --skip-tests) SKIP_TESTS=1;; esac; done
need gcloud; need terraform; need curl; need python3

log "Project $PROJECT_ID · $REGION · billing $BILLING_ACCOUNT_ID · admin $ADMIN_EMAIL"
log "1/6 Terraform state bucket"
"$ROOT/scripts/bootstrap.sh" "$PROJECT_ID" "$REGION" >/dev/null && ok "gs://$STATE_BUCKET"
tf_init
[ "$PLAN_ONLY" = 1 ] && { $TF plan -input=false; exit 0; }

log "2/6 Infrastructure"
$TF apply -input=false -auto-approve
ok "applied"

log "3/6 Secure build: test -> build -> SBOM -> vulnerability gate -> push -> attest (built-by-pipeline, scan-passed)"
IMG="$("$ROOT/scripts/build.sh" | tail -1)"; ok "image $IMG"; echo "$IMG" > "$ROOT/.last-image"

log "4/6 Cloud Deploy: release -> staging"
REL="$("$ROOT/scripts/release.sh" "$IMG" | tail -1)"; ok "release $REL"; echo "$REL" > "$ROOT/.last-release"
wait_rollout "$REL" staging SUCCEEDED 600

log "5/6 Promote to prod: approval -> canary (first deployment skips it) -> stable"
gcloud deploy releases promote --release "$REL" --delivery-pipeline "$PIPELINE" --region "$REGION" --project "$PROJECT_ID" --to-target prod --quiet >/dev/null
ok "promoted $REL to prod (prod requires approval)"
wait_rollout "$REL" prod PENDING_APPROVAL 300
approve_prod "$REL"
finish_prod "$REL" 900

if [ "$SKIP_TESTS" = 1 ]; then log "Skipping tests"; else log "6/6 Live test suite"; "$ROOT/scripts/test.sh"; fi
log "DONE — tear down with ./scripts/down.sh"
