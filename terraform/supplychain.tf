# Two independent attestors. An image may run only if BOTH have signed its digest:
#   built-by-pipeline : "this digest was produced by our Cloud Build pipeline"
#   scan-passed       : "this digest passed the vulnerability gate"
# Skipping the gate (or building elsewhere) therefore yields an image that cannot be deployed.
locals {
  attestors = {
    "built-by-pipeline" = "Built by the secure delivery pipeline"
    "scan-passed"       = "Passed the vulnerability gate (no fixable CRITICAL findings)"
  }
}

resource "google_kms_key_ring" "sign" {
  project    = var.project_id
  name       = "csd-${random_id.this.hex}"
  location   = var.region
  depends_on = [google_project_service.apis]
}

resource "google_kms_crypto_key" "sign" {
  for_each = local.attestors
  name     = each.key
  key_ring = google_kms_key_ring.sign.id
  purpose  = "ASYMMETRIC_SIGN"
  version_template {
    algorithm        = "EC_SIGN_P256_SHA256"
    protection_level = "SOFTWARE"
  }
}

data "google_kms_crypto_key_version" "sign" {
  for_each   = local.attestors
  crypto_key = google_kms_crypto_key.sign[each.key].id
}

resource "google_container_analysis_note" "att" {
  for_each = local.attestors
  project  = var.project_id
  name     = each.key
  attestation_authority {
    hint {
      human_readable_name = each.value
    }
  }
  depends_on = [google_project_service.apis]
}

resource "google_binary_authorization_attestor" "att" {
  for_each = local.attestors
  project  = var.project_id
  name     = each.key
  attestation_authority_note {
    note_reference = google_container_analysis_note.att[each.key].name
    public_keys {
      id = data.google_kms_crypto_key_version.sign[each.key].id
      pkix_public_key {
        public_key_pem      = data.google_kms_crypto_key_version.sign[each.key].public_key[0].pem
        signature_algorithm = data.google_kms_crypto_key_version.sign[each.key].public_key[0].algorithm
      }
    }
  }
}

# only the build identity may sign, and only through these keys
resource "google_kms_crypto_key_iam_member" "sign" {
  for_each      = local.attestors
  crypto_key_id = google_kms_crypto_key.sign[each.key].id
  role          = "roles/cloudkms.signerVerifier"
  member        = local.build_member
}

resource "google_binary_authorization_attestor_iam_member" "view" {
  for_each = local.attestors
  project  = var.project_id
  attestor = google_binary_authorization_attestor.att[each.key].name
  role     = "roles/binaryauthorization.attestorsViewer"
  member   = local.build_member
}

resource "google_container_analysis_note_iam_member" "attach" {
  for_each = local.attestors
  project  = var.project_id
  note     = google_container_analysis_note.att[each.key].name
  role     = "roles/containeranalysis.notes.attacher"
  member   = local.build_member
}

resource "google_project_iam_member" "occurrences" {
  project = var.project_id
  role    = "roles/containeranalysis.occurrences.editor"
  member  = local.build_member
}

# NOTE: this is the PROJECT's single Binary Authorization policy; destroying it restores allow-all.
resource "google_binary_authorization_policy" "this" {
  project                       = var.project_id
  global_policy_evaluation_mode = "ENABLE"
  default_admission_rule {
    evaluation_mode         = "REQUIRE_ATTESTATION"
    enforcement_mode        = "ENFORCED_BLOCK_AND_AUDIT_LOG"
    require_attestations_by = [for a in google_binary_authorization_attestor.att : a.name]
  }
}
