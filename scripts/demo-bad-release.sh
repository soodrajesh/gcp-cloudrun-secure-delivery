#!/usr/bin/env bash
# The bad-release drill, live: ship a build that returns 5xx on 60% of requests and watch the pipeline contain it.
#   1. secure build of a faulty version (it passes the gate: it is *buggy*, not vulnerable)      2. staging
#   3. promote + approve to prod -> canary 25 %: sample real traffic, measure the error share    4. roll back
#   5. verify prod is back to 100 % on the previous good release and errors are 0.
# Prints one JSON line per measurement so test.sh (and a reader) can assert on it.
source "$(dirname "$0")/lib.sh"; set +e
GOOD_REL="$(cat "$ROOT/.last-release")"
URL="$(prod_url)"
log "Baseline: prod before the bad release"
BASE="$(sample "$URL" 30)"; echo "BASELINE $BASE"

log "1/5 Build the faulty version (passes the vulnerability gate; it is a logic bug)"
IMG="$("$ROOT/scripts/build.sh" --tag "bad-$(date +%H%M%S)" --error-rate 60 | tail -1)"; ok "$IMG"
log "2/5 Release -> staging"
REL="$("$ROOT/scripts/release.sh" "$IMG" | tail -1)"; wait_rollout "$REL" staging SUCCEEDED 600
log "3/5 Promote -> approve -> prod canary 25 %"
gcloud deploy releases promote --release "$REL" --delivery-pipeline "$PIPELINE" --region "$REGION" --project "$PROJECT_ID" --to-target prod --quiet >/dev/null
wait_rollout "$REL" prod PENDING_APPROVAL 300; approve_prod "$REL"
T="$(wait_traffic quote-prod '^(25:[^ ]+ 75:[^ ]+|75:[^ ]+ 25:[^ ]+)$' 300)"; echo "TRAFFIC_AT_CANARY $T"
CANARY="$(sample "$URL" 100)"; echo "CANARY_SAMPLE $CANARY"

log "4/5 Detect and roll back (cancel the bad rollout, redeploy the previous good release)"
RO="$(rollout_of "$REL" prod)"
gcloud deploy rollouts cancel "$RO" --release "$REL" --delivery-pipeline "$PIPELINE" --region "$REGION" --project "$PROJECT_ID" --quiet >/dev/null 2>&1
gcloud deploy targets rollback prod --delivery-pipeline "$PIPELINE" --region "$REGION" --project "$PROJECT_ID" --release "$GOOD_REL" --quiet 2>&1 | tail -2
RB="$(gcloud deploy rollouts list --release "$GOOD_REL" --delivery-pipeline "$PIPELINE" --region "$REGION" --project "$PROJECT_ID" --filter='targetId=prod' --sort-by=~createTime --limit 1 --format='value(name.basename())')"
echo "ROLLBACK_ROLLOUT $RB"
for _ in $(seq 1 40); do [ "$(rollout_state "$GOOD_REL" "$RB")" = PENDING_APPROVAL ] && break; sleep 5; done
gcloud deploy rollouts approve "$RB" --release "$GOOD_REL" --delivery-pipeline "$PIPELINE" --region "$REGION" --project "$PROJECT_ID" --quiet >/dev/null; ok "approved rollback $RB"
for _ in $(seq 1 120); do
  [ "$(rollout_state "$GOOD_REL" "$RB")" = SUCCEEDED ] && break
  ph="$(rollout_phases "$GOOD_REL" "$RB")"; case "$ph" in *PENDING*) : ;; esac; sleep 8; done
echo "ROLLBACK_STATE $(rollout_state "$GOOD_REL" "$RB")"
log "5/5 Verify"
T="$(wait_traffic quote-prod '^100:[^ ]+$' 300)"; echo "TRAFFIC_AFTER $T"
AFTER="$(sample "$URL" 60)"; echo "AFTER_SAMPLE $AFTER"
echo "BAD_RELEASE $REL"
