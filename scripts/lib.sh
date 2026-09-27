#!/usr/bin/env bash
# Shared helpers for up.sh / down.sh / test.sh. Sourced, not executed.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✔ %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31m✘ %s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1${2:+ ($2)}"; }

[ -f "$ROOT/deploy.env" ] && set -a && . "$ROOT/deploy.env" && set +a

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
REGION="${REGION:-europe-west1}"
ADMIN_EMAIL="${ADMIN_EMAIL:-$(gcloud config get-value account 2>/dev/null)}"
ALERT_EMAIL="${ALERT_EMAIL:-$ADMIN_EMAIL}"
BUDGET_AMOUNT="${BUDGET_AMOUNT:-10}"
[ -n "$PROJECT_ID" ] || die "no project: set PROJECT_ID in deploy.env or 'gcloud config set project'"
BILLING_ACCOUNT_ID="${BILLING_ACCOUNT_ID:-$(gcloud billing projects describe "$PROJECT_ID" --format='value(billingAccountName)' 2>/dev/null | sed 's|billingAccounts/||')}"
[ -n "$BILLING_ACCOUNT_ID" ] || die "project has no billing account linked"

TF="terraform -chdir=$ROOT/terraform"
STATE_BUCKET="${PROJECT_ID}-tfstate"

export TF_VAR_project_id="$PROJECT_ID" TF_VAR_region="$REGION" TF_VAR_billing_account_id="$BILLING_ACCOUNT_ID" TF_VAR_alert_email="$ALERT_EMAIL" \
       TF_VAR_admin_email="$ADMIN_EMAIL" TF_VAR_budget_amount="$BUDGET_AMOUNT"

tf_init() { $TF init -input=false -backend-config="bucket=$STATE_BUCKET" >/dev/null; }

wait_for() { # <description> <timeout-seconds> <command...>
  local desc="$1" timeout="$2"; shift 2
  local end=$(( $(date +%s) + timeout ))
  until "$@" >/dev/null 2>&1; do
    [ "$(date +%s)" -lt "$end" ] || die "timed out after ${timeout}s waiting for: $desc"
    sleep 5
  done
  ok "$desc"
}


out() { $TF output -raw "$1"; }
PIPELINE=quote

# ---- Cloud Deploy helpers ----
rollout_of() { # <release> <target>  -> newest rollout name
  gcloud deploy rollouts list --release "$1" --delivery-pipeline "$PIPELINE" --region "$REGION" --project "$PROJECT_ID" \
    --filter="targetId=$2" --sort-by=~createTime --limit 1 --format='value(name.basename())' 2>/dev/null
}
rollout_state() { # <release> <rollout>
  gcloud deploy rollouts describe "$2" --release "$1" --delivery-pipeline "$PIPELINE" --region "$REGION" --project "$PROJECT_ID" --format='value(state)' 2>/dev/null
}
wait_rollout() { # <release> <target> <want-state> <timeout-s>
  local end=$(( $(date +%s) + $4 )) ro st
  while :; do
    ro="$(rollout_of "$1" "$2")"; st=""; [ -n "$ro" ] && st="$(rollout_state "$1" "$ro")"
    [ "$st" = "$3" ] && { ok "rollout $ro is $st"; return 0; }
    case "$st" in FAILED) die "rollout $ro FAILED";; esac
    [ "$(date +%s)" -lt "$end" ] || die "timed out waiting for $2 rollout to be $3 (last: ${st:-none})"
    sleep 6
  done
}

rollout_phases() { # <release> <rollout>  -> "SKIPPED SKIPPED PENDING"
  gcloud deploy rollouts describe "$2" --release "$1" --delivery-pipeline "$PIPELINE" --region "$REGION" --project "$PROJECT_ID" --format=json 2>/dev/null \
    | python3 -c "import sys,json; print(' '.join(p['state'] for p in json.load(sys.stdin).get('phases',[])))"
}
approve_prod() { # <release>  -> approves the newest prod rollout
  local ro; ro="$(rollout_of "$1" prod)"
  gcloud deploy rollouts approve "$ro" --release "$1" --delivery-pipeline "$PIPELINE" --region "$REGION" --project "$PROJECT_ID" --quiet >/dev/null
  ok "approved $ro"
}
# Wait for the prod rollout to finish. The FIRST deployment to an empty target skips both canary phases (there is no
# previous revision to split traffic against) and waits for a manual advance: do that once, automatically.
finish_prod() { # <release> [timeout-s]
  local rel="$1" end=$(( $(date +%s) + ${2:-900} )) ro st ph
  ro="$(rollout_of "$rel" prod)"
  while :; do
    st="$(rollout_state "$rel" "$ro")"
    [ "$st" = SUCCEEDED ] && { ok "rollout $ro is SUCCEEDED"; return 0; }
    [ "$st" = FAILED ] && die "rollout $ro FAILED"
    ph="$(rollout_phases "$rel" "$ro")"
    if [ "$ph" = "SKIPPED SKIPPED PENDING" ]; then
      log "first deployment to prod: canary phases skipped (nothing to split against), advancing to stable"
      gcloud deploy rollouts advance "$ro" --release "$rel" --delivery-pipeline "$PIPELINE" --region "$REGION" --project "$PROJECT_ID" --quiet >/dev/null
    fi
    [ "$(date +%s)" -lt "$end" ] || die "timed out waiting for prod rollout $ro (state $st, phases $ph)"
    sleep 8
  done
}
prod_url() { gcloud run services describe quote-prod --region "$REGION" --project "$PROJECT_ID" --format='value(status.url)'; }
traffic() { # <service> -> "25:rev-b 75:rev-a"
  gcloud run services describe "$1" --region "$REGION" --project "$PROJECT_ID" --format=json 2>/dev/null \
    | python3 -c "import sys,json; print(' '.join(f\"{t.get('percent',0)}:{t.get('revisionName','latest')}\" for t in json.load(sys.stdin)['status']['traffic']))"
}
wait_traffic() { # <service> <regex on traffic string> <timeout-s>
  local end=$(( $(date +%s) + $3 )) t
  while :; do t="$(traffic "$1")"; grep -qE "$2" <<<"$t" && { echo "$t"; return 0; }
    [ "$(date +%s)" -lt "$end" ] || { echo "$t"; return 1; }; sleep 5; done
}
# Count Container Analysis BUILD (provenance) occurrences for a digest reference. Uses the REST API
# directly: `gcloud artifacts docker images describe --show-provenance` does not reliably surface it.
build_occurrence_count() { # <repo/image@sha256:digest>
  local tok
  tok="$(gcloud auth print-access-token)"
  python3 -c "
import json, urllib.parse, urllib.request
f = 'resourceUrl=\"https://$1\" AND kind=\"BUILD\"'
req = urllib.request.Request(
    'https://containeranalysis.googleapis.com/v1/projects/$PROJECT_ID/occurrences?filter=' + urllib.parse.quote(f),
    headers={'Authorization': 'Bearer $tok'})
print(len(json.load(urllib.request.urlopen(req)).get('occurrences', [])))
"
}
sample() { # <url> <n>  -> JSON counter {"200 v1": 40, "500 -": 3}
  python3 - "$1" "$(gcloud auth print-identity-token 2>/dev/null | tail -1)" "$2" <<'PY'
import collections, json, sys, urllib.error, urllib.request
url, tok, n = sys.argv[1], sys.argv[2], int(sys.argv[3])
c = collections.Counter()
for _ in range(n):
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + tok})
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            c["200 " + r.headers.get("X-App-Version", "?")] += 1
    except urllib.error.HTTPError as e:
        c[f"{e.code} -"] += 1
print(json.dumps(c))
PY
}
