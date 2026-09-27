# ADR 0001 — Two independent attestors, not one

**Status:** accepted

Binary Authorization can enforce "signed by our pipeline", but that alone only proves *provenance* (this came from Cloud Build), not *quality* (it passed the vulnerability gate). A pipeline that builds and pushes an image, then crashes before the gate step, would still produce a validly-signed artifact under a single-attestor design.

Two attestors, signed at different steps with different KMS keys, close that gap: `built-by-pipeline` is signed right after push; `scan-passed` is signed only in the `attest` step, which runs after `gate` has exited 0. The Binary Authorization policy requires **both**. Proven live: an image attested only `built-by-pipeline` (gate skipped) is denied *by the `scan-passed` attestor specifically* — the denial names which guarantee is missing.

**Trade-off:** two KMS keys and two `sign-and-create` calls per build (seconds, not a real cost). The alternative — a single attestor whose note text claims "gate passed" — is not actually enforceable; Binary Authorization verifies a signature, not a claim.
