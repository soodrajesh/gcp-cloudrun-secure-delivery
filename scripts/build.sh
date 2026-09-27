#!/usr/bin/env bash
# Build one image through the secure pipeline. Prints the digest-pinned reference on the last line.
#   ./scripts/build.sh [--tag T] [--error-rate N] [--vuln-demo] [--rogue none|built]
# --vuln-demo  bakes in a CRITICAL CVE: the vulnerability gate must FAIL this build (exit != 0).
# --rogue      none|built|scan: uses cloudbuild-rogue.yaml, an image built outside the pipeline (test fixture).
source "$(dirname "$0")/lib.sh"
TAG="v$(date +%y%m%d-%H%M%S)"; ERR=0; VULN=false; ROGUE=""
while [ $# -gt 0 ]; do case "$1" in
  --tag) TAG="$2"; shift 2;; --error-rate) ERR="$2"; shift 2;; --vuln-demo) VULN=true; shift;; --rogue) ROGUE="$2"; shift 2;;
  *) die "unknown option $1";; esac; done
tf_init >/dev/null 2>&1
REPO="$(out artifact_repo)"; BUCKET="$(out work_bucket)"; BSA="$(out build_sa)"; KEYRING="$(out kms_keyring)"
COMMON=(--project "$PROJECT_ID" --region "$REGION" --service-account "projects/$PROJECT_ID/serviceAccounts/$BSA" --gcs-source-staging-dir "gs://$BUCKET/src")
if [ -n "$ROGUE" ]; then
  gcloud builds submit "${COMMON[@]}" --config cloudbuild-rogue.yaml \
    --substitutions "_REPO=$REPO,_TAG=$TAG,_ATTEST=$ROGUE,_KMS_KEYRING=$KEYRING" . >&2
else
  gcloud builds submit "${COMMON[@]}" --config cloudbuild.yaml \
    --substitutions "_REPO=$REPO,_TAG=$TAG,_ERROR_RATE=$ERR,_VULN_DEMO=$VULN,_BUCKET=$BUCKET,_KMS_KEYRING=$KEYRING" . >&2 || exit $?
fi
DIGEST="$(gcloud artifacts docker images describe "$REPO/quote:$TAG" --format='get(image_summary.digest)')"
echo "$REPO/quote@$DIGEST"
