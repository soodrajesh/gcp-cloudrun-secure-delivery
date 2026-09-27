# ADR 0002 — The vulnerability gate runs on the local image, before it is pushed

**Status:** accepted

`cloudbuild.yaml` builds, `docker save`s the image to a tarball, and scans **that tarball** with Trivy — `push` is a later step. A build that fails the gate (`trivy image --severity CRITICAL --ignore-unfixed --exit-code 1`) therefore never reaches Artifact Registry: there is no artifact to attest or deploy, so the two attestors ([ADR 0001](0001-two-attestors.md)) and Binary Authorization are defence in depth, not the only barrier.

Proven live: a build with PyYAML 5.3 baked in (CVE-2020-14343, CRITICAL, fixed in 5.4) exits non-zero at the `scan` step and the tag is never visible in `gcloud artifacts docker images list`.

**Scope:** the gate blocks CRITICAL findings **with a published fix** (`--ignore-unfixed`); a CRITICAL with no fix yet would not block a release that has no alternative. `--severity` and `--ignore-unfixed` are the two knobs to tighten for a stricter posture.
