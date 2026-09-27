# Live test results

Captured by `scripts/test.sh` on 2026-09-27T11:40:26Z against project `claude-code-507112` (europe-west1).

```

── 1. Topology ──
  PASS  delivery pipeline exists with staging -> prod stages, in order  [staging prod ]
  PASS  prod target requires approval  [staging=False prod=True ]
  PASS  …staging does not require approval  [absent: staging=True]
  PASS  Binary Authorization policy REQUIRES both attestors  [  requireAttestationsBy:   - projects/claude-code-507112/attestors/scan-passed   - projects/claude-code-507112]
  PASS  policy is ENFORCED with audit logging  [defaultAdmissionRule:   enforcementMode: ENFORCED_BLOCK_AND_AUDIT_LOG   evaluationMode: REQUIRE_ATTESTATION   ]
  PASS  registry tags are immutable  [True ]
  PASS  quote-staging enforces Binary Authorization (default policy)  [default ]
  PASS  quote-prod enforces Binary Authorization (default policy)  [default ]

── 2. The vulnerability gate stops a bad build BEFORE it is pushed ──
  building with a known CRITICAL CVE baked in (PyYAML 5.3)…
  PASS  build with a CRITICAL fixable CVE FAILS (non-zero exit)  [1 ]
  PASS  the failing step names the CVE  [Step #3 - "scan": Total: 0 (CRITICAL: 0) Step #3 - "scan": Total: 2 (CRITICAL: 2) Step #3 - "scan": │ PyYAML]
    │ PyYAML (METADATA) │ CVE-2020-14343 │ CRITICAL │ fixed  │ 5.3               │ 5.4           │ PyYAML: incomplete fix for CVE-2020-1747    │
    │                   │ CVE-2020-1747  │          │        │                   │ 5.3.1         │ PyYAML: arbitrary command execution through │
  PASS  the vulnerable image was never pushed to the registry  [absent: vuln-124026]

── 3. Evidence attached to the deployed image (v2-074222) ──
  PASS  attestation by 'built-by-pipeline' exists for the digest  [1 ]
  PASS  attestation by 'scan-passed' exists for the digest  [1 ]
  PASS  CycloneDX SBOM stored for this exact digest (>= 50 components)  [CycloneDX 1.6 116 ]
  building a fresh image to check provenance (older images may predate this repo's provenance fix)…
  PASS  SLSA build provenance (a Container Analysis BUILD occurrence) is attached  [3 ]

── 4. Admission control: what cannot run ──
  building three images OUTSIDE the trusted pipeline (no attestation / built-only / scan-only)…
  PASS  image with NO attestation is denied  [Deploying container to Cloud Run service [rogue] in project [claude-code-507112] region [europe-west1] Deployi]
  PASS  built-only image (gate skipped) is denied, by attestor scan-passed  [Deploying container to Cloud Run service [rogue] in project [claude-code-507112] region [europe-west1] Deployi]
  PASS  scan-only image (built elsewhere) is denied, by attestor built-by-pipeline  [Deploying container to Cloud Run service [rogue] in project [claude-code-507112] region [europe-west1] Deployi]
  PASS  the pipeline's image (both attestations) IS admitted  [Deploying container to Cloud Run service [rogue] in project [claude-code-507112] region [europe-west1] Deployi]
  PASS  re-pointing an existing tag at other bits is refused (immutable tags)  [ERROR: (gcloud.artifacts.docker.tags.add) FAILED_PRECONDITION: cannot delete tag v2-074222. The repository has]

── 5. Progressive delivery: staging -> approval -> canary 25 % -> 50 % -> 100 % ──
  building and releasing a new good version…
  PASS  staging serves the new version  [{"200 v2-124026": 3} ]
  PASS  prod still serves ONLY the previous version before approval  [{"200 v2-074222": 20} ]
  PASS  prod rollout is PENDING_APPROVAL (a human gate)  [PENDING_APPROVAL ]
  PASS  …and prod is untouched while it waits  [{"200 v2-074222": 10} ]
  PASS  canary phase 1: traffic split 25 / 75  [75:quote-prod-mujgnd4q 25:quote-prod-mujrb6xi ]
    sampled 100 requests at canary-25: {"200 v2-074222": 78, "200 v2-124026": 22}
  PASS  roughly a quarter of real requests hit the new version (10-45 of 100)  [22 ]
  PASS  canary phase 2 (automatic after a soak): 50 / 50  [50:quote-prod-mujgnd4q 50:quote-prod-mujrb6xi ]
  PASS  final: 100 % on one revision  [100:quote-prod-mujrb6xi ]
  PASS  final: every sampled request served by the new version  [{"200 v2-124026": 40} ]

── 6. Bad release drill: a faulty version is contained by the canary and rolled back ──
    BASELINE {"200 v2-124026": 30}
    TRAFFIC_AT_CANARY 75:quote-prod-mujrb6xi 25:quote-prod-mujrl647
    CANARY_SAMPLE {"200 v2-124026": 78, "500 -": 16, "200 bad-125507": 6}
    ROLLBACK_STATE SUCCEEDED
    TRAFFIC_AFTER 100:quote-prod-mujrb6xi
    AFTER_SAMPLE {"200 v2-124026": 60}
  PASS  baseline before the bad release: zero errors  [{"200 v2-124026": 30} ]
  PASS  baseline had no 5xx  [absent: "500]
  PASS  at canary-25 the faulty version is visibly failing (some 5xx, but blast radius limited: < 40 of 100)  [16 ]
  PASS  rollback rollout SUCCEEDED  [SUCCEEDED ]
  PASS  after rollback: 100 % of traffic on one revision  [100:quote-prod-mujrb6xi ]
  PASS  after rollback: zero errors in 60 requests  [0 ]

── 7. Access and identities ──
  PASS  prod is not public (unauthenticated request -> 403)  [403 ]
  PASS  quote-staging: no allUsers / allAuthenticatedUsers invoker  [absent: allUsers|allAuthenticatedUsers]
  PASS  quote-prod: no allUsers / allAuthenticatedUsers invoker  [absent: allUsers|allAuthenticatedUsers]
  PASS  no user-managed service-account keys exist  [0 ]
  PASS  runtime identity csd-app holds no project roles  [0 ]
  PASS  build identity cannot deploy (no run.* / clouddeploy.* role)  [absent: roles/run\.|roles/clouddeploy]
  PASS  only the build identity may sign with the attestation keys  [['serviceAccount:csd-build@claude-code-507112.iam.gserviceaccount.com'] ]

── 8. Operability ──
  PASS  5xx-ratio alert on quote-prod exists  [Delivery: quote-prod 5xx ratio > 5% (canary or release is bad) ]
  PASS  dashboard exists  [Secure delivery ]
```

**Result: 44 passed, 0 failed.**
