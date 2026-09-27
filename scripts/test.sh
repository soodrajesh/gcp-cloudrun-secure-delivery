#!/usr/bin/env bash
# Live proof against the running system. Every check asserts something observed, not configured.
# Writes docs/test-results.md. Exit code = number of failed checks.
#   SKIP_DELIVERY=1  skip §5 (a full canary release), SKIP_DRILL=1 skip §6 (the bad-release drill): for quick iteration only.
source "$(dirname "$0")/lib.sh"; set +e
need gcloud; need curl; need python3
PASS=0; FAIL=0; OUT="$ROOT/docs/test-results.md"; TMP="$ROOT/.test-tmp"; mkdir -p "$TMP"
{ echo "# Live test results"; echo; echo "Captured by \`scripts/test.sh\` on $(date -u +%FT%TZ) against project \`$PROJECT_ID\` ($REGION)."; echo; echo '```'; } > "$OUT"
say()   { echo "$*" | tee -a "$OUT"; }
check() { # <name> <expected-regex> <actual>
  if grep -qE -- "$2" <<<"$3"; then PASS=$((PASS+1)); say "  PASS  $1  [$(head -c 110 <<<"$3" | tr '\n' ' ')]"
  else FAIL=$((FAIL+1)); say "  FAIL  $1  (wanted /$2/, got: $(head -c 220 <<<"$3" | tr '\n' ' '))"; fi
}
check_not() { # <name> <forbidden-regex> <actual>
  if grep -qE -- "$2" <<<"$3"; then FAIL=$((FAIL+1)); say "  FAIL  $1  (found /$2/ in: $(head -c 200 <<<"$3" | tr '\n' ' '))"
  else PASS=$((PASS+1)); say "  PASS  $1  [absent: $2]"; fi
}
section() { say ""; say "── $* ──"; }
jq_() { python3 -c "import sys,json; d=json.load(sys.stdin); print($1)"; }

P="$PROJECT_ID"; RUN="$(date +%H%M%S)"
REPO="$(out artifact_repo)"; BUCKET="$(out work_bucket)"; KEYRING="$(out kms_keyring)"
GOOD_IMG="$(cat "$ROOT/.last-image")"
GOOD_TAG="$(gcloud artifacts docker images list "$REPO/quote" --include-tags --format='value(version,tags)' 2>/dev/null | awk -F'\t' -v d="${GOOD_IMG##*@}" '$1==d{print $2}' | tail -1)"
BASE_POLICY="$(gcloud container binauthz policy export --project "$P" 2>/dev/null)"

# `gcloud deploy ... describe` wraps its JSON in extra keys ("Delivery Pipeline", "Target", "Active
# Pipeline", ...) that vary by command, which breaks plain `--format=value(...)` paths. `list` does not.
section "1. Topology"
gcloud deploy targets list --region "$REGION" --project "$P" --format=json > "$TMP/targets.json"
gcloud deploy delivery-pipelines list --region "$REGION" --project "$P" --format=json > "$TMP/pipelines.json"
STAGES="$(python3 -c "import json; d=[p for p in json.load(open('$TMP/pipelines.json')) if p['name'].endswith('/$PIPELINE')][0]; print(' '.join(s['targetId'] for s in d['serialPipeline']['stages']))")"
check "delivery pipeline exists with staging -> prod stages, in order" '^staging prod$' "$STAGES"
APPROVALS="$(python3 -c "import json; d=json.load(open('$TMP/targets.json')); print(' '.join(t['targetId']+'='+str(t.get('requireApproval', False)) for t in d['targets']))")"
check "prod target requires approval" 'prod=True' "$APPROVALS"
check_not "…staging does not require approval" 'staging=True' "$APPROVALS"
check "Binary Authorization policy REQUIRES both attestors" 'built-by-pipeline.*scan-passed|scan-passed.*built-by-pipeline' "$(grep -A4 requireAttestationsBy <<<"$BASE_POLICY" | tr '\n' ' ')"
check "policy is ENFORCED with audit logging" 'ENFORCED_BLOCK_AND_AUDIT_LOG' "$BASE_POLICY"
check "registry tags are immutable" 'True|true' "$(gcloud artifacts repositories describe apps --location "$REGION" --project "$P" --format='value(dockerConfig.immutableTags)')"
for s in quote-staging quote-prod; do
  check "$s enforces Binary Authorization (default policy)" 'default' \
    "$(gcloud run services describe "$s" --region "$REGION" --project "$P" --format='value(metadata.annotations."run.googleapis.com/binary-authorization")')"
done

section "2. The vulnerability gate stops a bad build BEFORE it is pushed"
say "  building with a known CRITICAL CVE baked in (PyYAML 5.3)…"
"$ROOT/scripts/build.sh" --vuln-demo --tag "vuln-$RUN" >"$TMP/vuln.out" 2>"$TMP/vuln.err"; rc=$?
check "build with a CRITICAL fixable CVE FAILS (non-zero exit)" '^[1-9]' "$rc"
VB="$(gcloud builds list --region "$REGION" --project "$P" --limit 1 --format='value(id)')"
gcloud beta builds log "$VB" --region "$REGION" --project "$P" 2>&1 | grep 'Step #3' | grep -E "CVE-|Total:" > "$TMP/vuln-findings.txt"
check "the failing step names the CVE" 'CVE-2020-14343' "$(cat "$TMP/vuln-findings.txt")"
say "$(sed 's/^Step #3 - "scan": *//' "$TMP/vuln-findings.txt" | grep -E 'CVE-' | head -3 | sed 's/^/    /')"
check_not "the vulnerable image was never pushed to the registry" "vuln-$RUN" "$(gcloud artifacts docker images list "$REPO/quote" --include-tags --format='value(tags)' 2>/dev/null)"

section "3. Evidence attached to the deployed image ($GOOD_TAG)"
for a in built-by-pipeline scan-passed; do
  check "attestation by '$a' exists for the digest" '^1$' "$(gcloud container binauthz attestations list --attestor="$a" --attestor-project="$P" --artifact-url="$GOOD_IMG" --format='value(name.basename())' 2>/dev/null | wc -l | tr -d ' ')"
done
D="${GOOD_IMG##*sha256:}"
SBOM="$(gcloud storage cat "gs://$BUCKET/sbom/$D.cdx.json" 2>/dev/null | jq_ "d['bomFormat'], d['specVersion'], len(d['components'])")"
check "CycloneDX SBOM stored for this exact digest (>= 50 components)" '^CycloneDX [0-9.]+ ([5-9][0-9]|[1-9][0-9]{2,})$' "$SBOM"
say "  building a fresh image to check provenance (older images may predate this repo's provenance fix)…"
PIMG="$("$ROOT/scripts/build.sh" --tag "prov-$RUN" | tail -1)"
check "SLSA build provenance (a Container Analysis BUILD occurrence) is attached" '^[1-9]' "$(build_occurrence_count "$PIMG")"

section "4. Admission control: what cannot run"
say "  building three images OUTSIDE the trusted pipeline (no attestation / built-only / scan-only)…"
for k in none built scan; do ( "$ROOT/scripts/build.sh" --rogue "$k" --tag "rogue-$k-$RUN" 2>/dev/null | tail -1 > "$TMP/rogue-$k.ref" ) & done; wait
deploy() { gcloud run deploy rogue --image "$1" --region "$REGION" --project "$P" --service-account "$(out app_sa)" --no-allow-unauthenticated --binary-authorization=default --quiet 2>&1; }
r=$(deploy "$(cat "$TMP/rogue-none.ref")");  check "image with NO attestation is denied" 'not authorized by policy' "$r"
r=$(deploy "$(cat "$TMP/rogue-built.ref")"); check "built-only image (gate skipped) is denied, by attestor scan-passed" 'denied by attestor .*scan-passed' "$r"
r=$(deploy "$(cat "$TMP/rogue-scan.ref")");  check "scan-only image (built elsewhere) is denied, by attestor built-by-pipeline" 'denied by attestor .*built-by-pipeline' "$r"
r=$(deploy "$GOOD_IMG");                      check "the pipeline's image (both attestations) IS admitted" 'Service \[rogue\] revision|has been deployed|Done' "$r"
gcloud run services delete rogue --region "$REGION" --project "$P" --quiet >/dev/null 2>&1
r=$(gcloud artifacts docker tags add "$(cat "$TMP/rogue-none.ref")" "$REPO/quote:$GOOD_TAG" 2>&1)
check "re-pointing an existing tag at other bits is refused (immutable tags)" 'immutable|already exists|FAILED_PRECONDITION|denied|ALREADY_EXISTS' "$r"

if [ "${SKIP_DELIVERY:-0}" != 1 ]; then
section "5. Progressive delivery: staging -> approval -> canary 25 % -> 50 % -> 100 %"
URL="$(prod_url)"
# Whatever prod is ACTUALLY serving right now (not .last-image, which can go stale between runs).
V1="$(sample "$URL" 1 | python3 -c "import sys,json; d=json.loads(sys.stdin.read()); print(next(iter(d)).split(' ',1)[1])" 2>/dev/null)"
say "  building and releasing a new good version…"
IMG2="$("$ROOT/scripts/build.sh" --tag "v2-$RUN" | tail -1)"; REL2="$("$ROOT/scripts/release.sh" "$IMG2" | tail -1)"
wait_rollout "$REL2" staging SUCCEEDED 600 >/dev/null
STG="$(gcloud run services describe quote-staging --region "$REGION" --project "$P" --format='value(status.url)')"
check "staging serves the new version" "v2-$RUN" "$(sample "$STG" 3)"
check "prod still serves ONLY the previous version before approval" "^\{\"200 $V1\": [0-9]+\}$" "$(sample "$URL" 20)"
gcloud deploy releases promote --release "$REL2" --delivery-pipeline "$PIPELINE" --region "$REGION" --project "$P" --to-target prod --quiet >/dev/null
wait_rollout "$REL2" prod PENDING_APPROVAL 300 >/dev/null
check "prod rollout is PENDING_APPROVAL (a human gate)" 'PENDING_APPROVAL' "$(rollout_state "$REL2" "$(rollout_of "$REL2" prod)")"
check "…and prod is untouched while it waits" "^\{\"200 $V1\": [0-9]+\}$" "$(sample "$URL" 10)"
approve_prod "$REL2" >/dev/null
T="$(wait_traffic quote-prod '^(25:[^ ]+ 75:[^ ]+|75:[^ ]+ 25:[^ ]+)$' 300)"; check "canary phase 1: traffic split 25 / 75" '25:.*75:|75:.*25:' "$T"
S="$(sample "$URL" 100)"; say "    sampled 100 requests at canary-25: $S"
NEW=$(jq_ "sum(v for k,v in json.loads('''$S''').items() if k.endswith('v2-$RUN'))" <<<'{}')
check "roughly a quarter of real requests hit the new version (10-45 of 100)" '^([1-3][0-9]|4[0-5])$' "$NEW"
T="$(wait_traffic quote-prod '^(50:[^ ]+ 50:[^ ]+)$' 300)"; check "canary phase 2 (automatic after a soak): 50 / 50" '50:.*50:' "$T"
finish_prod "$REL2" 600 >/dev/null
T="$(traffic quote-prod)"; check "final: 100 % on one revision" '^100:[^ ]+$' "$T"
check "final: every sampled request served by the new version" "^\{\"200 v2-$RUN\": 40\}$" "$(sample "$URL" 40)"
echo "v2-$RUN" > "$TMP/current-tag"; echo "$REL2" > "$ROOT/.last-release"
fi

if [ "${SKIP_DRILL:-0}" != 1 ]; then
section "6. Bad release drill: a faulty version is contained by the canary and rolled back"
"$ROOT/scripts/demo-bad-release.sh" > "$TMP/drill.out" 2>&1
grep -E '^(BASELINE|TRAFFIC_AT_CANARY|CANARY_SAMPLE|ROLLBACK_STATE|TRAFFIC_AFTER|AFTER_SAMPLE) ' "$TMP/drill.out" | sed 's/^/    /' | tee -a "$OUT"
CS="$(sed -n 's/^CANARY_SAMPLE //p' "$TMP/drill.out")"; AS="$(sed -n 's/^AFTER_SAMPLE //p' "$TMP/drill.out")"
E=$(jq_ "sum(v for k,v in json.loads('''$CS''').items() if k.startswith('500'))" <<<'{}'); AE=$(jq_ "sum(v for k,v in json.loads('''$AS''').items() if k.startswith('500'))" <<<'{}')
check "baseline before the bad release: zero errors" '"200 ' "$(sed -n 's/^BASELINE //p' "$TMP/drill.out")"
check_not "baseline had no 5xx" '"500' "$(sed -n 's/^BASELINE //p' "$TMP/drill.out")"
check "at canary-25 the faulty version is visibly failing (some 5xx, but blast radius limited: < 40 of 100)" '^([1-9]|[1-3][0-9])$' "$E"
check "rollback rollout SUCCEEDED" 'SUCCEEDED' "$(sed -n 's/^ROLLBACK_STATE //p' "$TMP/drill.out")"
check "after rollback: 100 % of traffic on one revision" '^100:' "$(sed -n 's/^TRAFFIC_AFTER //p' "$TMP/drill.out")"
check "after rollback: zero errors in 60 requests" '^0$' "$AE"
fi

section "7. Access and identities"
PUB="$(curl -s -o /dev/null -w '%{http_code}' "$(prod_url)/")"
check "prod is not public (unauthenticated request -> 403)" '^403$' "$PUB"
for s in quote-staging quote-prod; do
  check_not "$s: no allUsers / allAuthenticatedUsers invoker" 'allUsers|allAuthenticatedUsers' "$(gcloud run services get-iam-policy "$s" --region "$REGION" --project "$P" --format='value(bindings.members)')"
done
keys=0; for sa in csd-build csd-deploy csd-app; do n=$(gcloud iam service-accounts keys list --iam-account "$sa@$P.iam.gserviceaccount.com" --managed-by=user --format='value(name)' 2>/dev/null | grep -c .); keys=$((keys+n)); done
check "no user-managed service-account keys exist" '^0$' "$keys"
check "runtime identity csd-app holds no project roles" '^0$' "$(gcloud projects get-iam-policy "$P" --flatten=bindings --filter="bindings.members:serviceAccount:csd-app@$P.iam.gserviceaccount.com" --format='value(bindings.role)' | grep -c .)"
check_not "build identity cannot deploy (no run.* / clouddeploy.* role)" 'roles/run\.|roles/clouddeploy' "$(gcloud projects get-iam-policy "$P" --flatten=bindings --filter="bindings.members:serviceAccount:csd-build@$P.iam.gserviceaccount.com" --format='value(bindings.role)')"
check "only the build identity may sign with the attestation keys" 'csd-build' "$(gcloud kms keys get-iam-policy scan-passed --keyring "$KEYRING" --location "$REGION" --project "$P" --format='value(bindings.members)')"

section "8. Operability"
pol="$(gcloud monitoring policies list --project "$P" --format='value(displayName)')"
check "5xx-ratio alert on quote-prod exists" 'quote-prod 5xx ratio' "$pol"
check "dashboard exists" 'Secure delivery' "$(gcloud monitoring dashboards list --project "$P" --format='value(displayName)')"

say '```'; echo >> "$OUT"; echo "**Result: $PASS passed, $FAIL failed.**" >> "$OUT"
echo; [ "$FAIL" = 0 ] && ok "$PASS/$((PASS+FAIL)) checks passed" || warn "$FAIL failed, $PASS passed"
exit "$FAIL"
