#!/usr/bin/env python3
"""Generates docs/img/architecture.svg (PNG via docs/diagrams/render.py).

    python3 docs/diagrams/architecture.py
"""

import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from archlib import Diagram  # noqa: E402

OUT = os.path.join(os.path.dirname(__file__), "..", "img", "architecture.svg")

W, H = 1780, 1610
d = Diagram(W, H, "Secure Delivery to Cloud Run on Google Cloud",
            "Cloud Build · vulnerability gate · SBOM + SLSA · KMS attestations · Binary Authorization · Cloud Deploy canary · Terraform")

d.group(190, 100, 1480, 760, "Google Cloud project  ·  europe-west1", "#1a73e8", dash=False, fill="#f8faff", label_w=330)

# ── lane 1: BUILD ────────────────────────────────────────────────────────────────────────────────
d.text(220, 150, "BUILD", 12.5, "#5f6368", "700")
d.node("dev", 70, 250, "Developer", "user", "actor", "git push")
d.node("cb", 360, 250, "", "pipeline", "dev")
d.text(360, 172, "Cloud Build", 12.5, "#202124", "600", "middle")
d.text(360, 186, "dedicated SA · tests", 10.5, "#5f6368", "400", "middle")
d.text(360, 199, "build · SLSA provenance", 10.5, "#5f6368", "400", "middle")
d.node("gate", 690, 250, "Vulnerability gate", "filter", "security", "Trivy on the local image\nfails on fixable CRITICAL")
d.node("ar", 1020, 250, "Artifact Registry", "registry", "dev", "immutable tags\ndigest-pinned")
d.node("sbom", 1340, 250, "SBOM (CycloneDX)", "policy", "data", "stored per digest\nin Cloud Storage")
d.edge("dev", "cb", "h", num=1, label="push / PR")
d.edge("cb", "gate", "h", num=2, label="image tarball")
d.edge("gate", "ar", "h", num=3, label="pass → push")
d.path([(1050, 235), (1310, 235)], num=None)
d.text(1180, 226, "SBOM", 10.5, "#5f6368", "400", "middle")
d.text(690, 178, "A failing image is never pushed,", 11, "#d93025", "600", "middle")
d.text(690, 192, "so it can never be attested or deployed", 11, "#d93025", "600", "middle")

# ── lane 2: TRUST ────────────────────────────────────────────────────────────────────────────────
d.text(220, 380, "TRUST", 12.5, "#5f6368", "700")
d.node("kms", 360, 470, "Cloud KMS", "key", "security", "2 asymmetric keys\nsigner: build SA only")
d.node("att", 690, 470, "Attestations", "shield", "security", "built-by-pipeline\nscan-passed")
d.node("ba", 1020, 470, "", "wall", "security")
d.text(1020, 395, "Binary Authorization", 12.5, "#202124", "600", "middle")
d.text(1020, 409, "policy: BOTH required", 10.5, "#5f6368", "400", "middle")
d.text(1020, 422, "enforced + audit-logged", 10.5, "#5f6368", "400", "middle")
d.edge("kms", "att", "h", label="signatures")
d.edge("att", "ba", "h", label="verified against")
d.edge("cb", "kms", "v", num=4, label="sign digest (after the gate passes)", lab_dy=0, half_a=30, half_b=30)

# ── lane 3: DELIVER ──────────────────────────────────────────────────────────────────────────────
d.text(220, 640, "DELIVER", 12.5, "#5f6368", "700")
d.node("cd", 360, 720, "Cloud Deploy", "pipeline", "compute", "release by digest\nserial pipeline")
d.node("stg", 690, 720, "quote-staging", "run", "compute", "Cloud Run\nautomatic")
d.node("human", 1020, 720, "Approver", "user", "actor", "prod requires\nhuman approval")
d.node("prod", 1340, 720, "quote-prod", "run", "compute", "canary 25 → 50 → 100 %\nauto-advance after soak")
d.node("client", 1600, 720, "Clients", "user", "actor", "IAM-authenticated")
d.edge("cd", "stg", "h", num=5, label="deploy")
d.edge("stg", "human", "h", num=7, label="promote")
d.edge("human", "prod", "h", num=8, label="approve")
d.edge("prod", "client", "h")
d.path([(1020, 502), (1020, 590), (690, 590), (690, 688)], num=6, color="#d93025")
d.path([(1020, 590), (1340, 590), (1340, 688)], num=None, color="#d93025")
d.text(1020, 612, "admission check on EVERY revision (staging and prod)", 11.5, "#d93025", "600", "middle")

# ── ops / governance ─────────────────────────────────────────────────────────────────────────────
d.band(190, 900, 1480, 190, "OBSERVABILITY  ·  the pipeline reports on itself", "#1e8e3e", "#f6fcf8")
d.node("o1", 330, 1000, "Dashboard", "chart", "ops", "traffic + 5xx by revision")
d.node("o2", 700, 1000, "5xx-ratio alert", "bolt", "ops", "> 5 % for 2 min on prod\n→ roll back")
d.node("o3", 1070, 1000, "Audit logs", "policy", "ops", "every Binary Authorization\nallow / deny")
d.node("o4", 1440, 1000, "Budget", "money", "ops", "€ alerts 50 / 100 %")

d.band(190, 1110, 1480, 130, "GOVERNANCE  ·  preventive controls", "#d93025", "#fff8f7")
d.text(220, 1154, "Build, deploy and runtime are three different service accounts: the builder cannot deploy, the deployer cannot sign, the runtime has no roles · No keys anywhere", 12.5, "#3c4043")
d.text(220, 1178, "Registry tags are immutable and deploys use digests · prod is never public (IAM-authenticated) · rollback is a first-class, approved rollout", 12.5, "#3c4043")
d.text(220, 1202, "The Binary Authorization policy is project-wide: destroying this stack restores the project to allow-all", 12.5, "#3c4043")

d.legend(34, 1270, "Numbered flows", [
    ("1", "A push runs Cloud Build as a dedicated service account; unit tests run first"),
    ("2", "The image is built and saved as a tarball; a CycloneDX SBOM is produced and Trivy scans it: any CRITICAL vulnerability with a fix fails the build"),
    ("3", "Only a passing image is pushed (tags are immutable); Cloud Build attaches SLSA provenance and the SBOM is stored against the digest"),
    ("4", "Cloud KMS signs two attestations for the digest: built-by-pipeline and scan-passed (different keys; only the build SA may sign)"),
    ("5", "A Cloud Deploy release pins the digest and rolls out to staging automatically"),
    ("6", "Cloud Run asks Binary Authorization on every revision: both attestations must verify, otherwise the revision is denied and audit-logged"),
    ("7", "Promotion to prod is an explicit step, then a human approves"),
    ("8", "Prod rolls out as a canary (25 %, 50 %, 100 %, advancing after a soak); a bad canary is cancelled and rolled back with one approved command"),
], w=1710)
d.key(34, 1500)

if __name__ == "__main__":
    d.save(OUT)
    print("wrote", os.path.abspath(OUT))
