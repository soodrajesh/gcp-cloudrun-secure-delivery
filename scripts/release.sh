#!/usr/bin/env bash
# Create a Cloud Deploy release from a digest-pinned image. Prints the release name.
#   ./scripts/release.sh <repo/quote@sha256:...> [release-name]
source "$(dirname "$0")/lib.sh"
IMG="${1:?usage: release.sh <image@digest> [release-name]}"
REL="${2:-rel-$(date +%y%m%d-%H%M%S)}"
BUCKET="$(cd "$ROOT" && tf_init >/dev/null 2>&1; out work_bucket)"
SRC="$(mktemp -d)"
for env in staging prod; do sed -e "s/__ENV__/$env/g" -e "s/__PROJECT__/$PROJECT_ID/g" run/service.yaml.tmpl > "$SRC/run-$env.yaml"; done
cp skaffold.yaml "$SRC/"
gcloud deploy releases create "$REL" --project "$PROJECT_ID" --region "$REGION" --delivery-pipeline "$PIPELINE" \
  --source "$SRC" --skaffold-file skaffold.yaml --images "quote=$IMG" --gcs-source-staging-dir "gs://$BUCKET/deploy-src" >&2
rm -rf "$SRC"; echo "$REL"
