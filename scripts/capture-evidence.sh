#!/usr/bin/env bash
# Re-captures docs/evidence/*.txt from the LIVE system (run after up.sh + test.sh).
# Render: python3 docs/diagrams/termshot.py "<title>" docs/evidence/<f>.txt docs/img/<f>.png
source "$(dirname "$0")/lib.sh"; set +e
E="$ROOT/docs/evidence"; TMP="$ROOT/.test-tmp"; mkdir -p "$E" "$TMP"; P="$PROJECT_ID"
GOOD_IMG="$(cat "$ROOT/.last-image" 2>/dev/null)"
run() { echo "\$ $1"; eval "$1" 2>&1; echo; }

{ echo "\$ ./scripts/build.sh --vuln-demo   # bakes in PyYAML 5.3, CVE-2020-14343 (CRITICAL, fixed in 5.4)"
  "$ROOT/scripts/build.sh" --vuln-demo --tag "evidence-vuln" >"$TMP/ev-vuln.out" 2>"$TMP/ev-vuln.err"; rc=$?
  echo "(build exit code: $rc)"; echo
  VB="$(gcloud builds list --region "$REGION" --project "$P" --limit 1 --format='value(id)')"
  echo "\$ # from the 'scan' step of build $VB"
  gcloud beta builds log "$VB" --region "$REGION" --project "$P" 2>&1 | grep 'Step #3' | sed 's/^Step #3 - "scan": *//' | grep -vE '^$'
} > "$E/vuln-gate.txt"

{ for k in none built scan; do ( "$ROOT/scripts/build.sh" --rogue "$k" --tag "ev-rogue-$k" 2>/dev/null | tail -1 > "$TMP/ev-rogue-$k.ref" ) & done; wait
  for k in none built scan; do
    echo "\$ gcloud run deploy rogue --image <$k-attested image>"
    gcloud run deploy rogue --image "$(cat "$TMP/ev-rogue-$k.ref")" --region "$REGION" --project "$P" --service-account "$(out app_sa)" --no-allow-unauthenticated --binary-authorization=default --quiet 2>&1 | grep -E "ERROR|denied"; echo
  done
  echo "\$ gcloud run deploy rogue --image <the pipeline's image, both attestations>"
  gcloud run deploy rogue --image "$GOOD_IMG" --region "$REGION" --project "$P" --service-account "$(out app_sa)" --no-allow-unauthenticated --binary-authorization=default --quiet 2>&1 | tail -2
  gcloud run services delete rogue --region "$REGION" --project "$P" --quiet >/dev/null 2>&1
} > "$E/admission-denials.txt"

{ run "gcloud deploy delivery-pipelines describe $PIPELINE --region $REGION --project $P --format='value(serialPipeline.stages[].targetId,serialPipeline.stages[].strategy.canary.canaryDeployment.percentages)'"
  run "gcloud container binauthz policy export --project $P"
} > "$E/topology.txt"

if [ -f "$TMP/drill.out" ]; then cp "$TMP/drill.out" "$E/drill.txt"; else "$ROOT/scripts/demo-bad-release.sh" > "$E/drill.txt" 2>&1; fi

ok "evidence written to docs/evidence/"
