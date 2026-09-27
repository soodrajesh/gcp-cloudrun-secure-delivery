# Threat model (STRIDE, supply-chain scope)

| Threat | Control | Proven by |
|---|---|---|
| **S**poofed build (image not from our pipeline) | Binary Authorization requires `built-by-pipeline`, signed only by `csd-build` | test §4: no-attestation image denied |
| **T**ampering: a vulnerable image deployed | Vulnerability gate runs before push; `scan-passed` attestor only signed after it passes | test §2 (CVE build fails, never pushed), §4 (built-only image denied by `scan-passed`) |
| **T**ampering: a tag re-pointed to different bits | Immutable tags on the registry | test §4 |
| **R**epudiation: "which build produced this?" | SLSA provenance (Container Analysis BUILD occurrence) + SBOM per digest, both queryable | test §3 |
| **I**nformation disclosure: prod reachable without auth | Cloud Run requires IAM; no `allUsers` | test §7 |
| **D**enial of service: a bad release breaks prod | Canary limits blast radius to 25 % automatically; 5xx-ratio alert; one-command rollback | test §6 (the drill), §8 |
| **E**levation: build identity deploys, or deploy identity signs | Three separate service accounts, each least-privilege; verified to hold none of the other's roles | test §7 |
| Compromised KMS signer | Only `csd-build` holds `cloudkms.signerVerifier` on the attestation keys | test §7 |

**Out of scope:** source-code provenance (who wrote the commit, branch protection), runtime attestation (an already-running container is not re-verified), CMEK, multi-region, a real staging → prod promotion gate beyond human approval (e.g. automated smoke tests before promote).
