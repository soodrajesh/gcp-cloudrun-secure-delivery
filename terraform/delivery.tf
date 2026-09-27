locals {
  targets = {
    staging = { approval = false }
    prod    = { approval = true }
  }
}

resource "google_clouddeploy_target" "t" {
  for_each         = local.targets
  project          = var.project_id
  location         = var.region
  name             = each.key
  description      = "quote on Cloud Run (${each.key})"
  require_approval = each.value.approval

  run {
    location = "projects/${var.project_id}/locations/${var.region}"
  }
  execution_configs {
    usages            = ["RENDER", "DEPLOY"]
    service_account   = google_service_account.sa["csd-deploy"].email
    artifact_storage  = "gs://${google_storage_bucket.work.name}/deploy"
    execution_timeout = "1800s"
  }
  depends_on = [google_service_account_iam_member.deploy_actas_self]
}

resource "google_clouddeploy_delivery_pipeline" "quote" {
  project     = var.project_id
  location    = var.region
  name        = "quote"
  description = "staging (immediate) -> prod (approval, then 25% -> 50% -> 100% canary)"

  serial_pipeline {
    stages {
      target_id = google_clouddeploy_target.t["staging"].name
      profiles  = ["staging"]
    }
    stages {
      target_id = google_clouddeploy_target.t["prod"].name
      profiles  = ["prod"]
      strategy {
        canary {
          runtime_config {
            cloud_run {
              automatic_traffic_control = true
            }
          }
          canary_deployment {
            percentages = [25, 50]
            verify      = false
          }
        }
      }
    }
  }
}

# a healthy canary advances by itself after a soak; an operator (or an alert) can still stop it
resource "google_clouddeploy_automation" "advance" {
  project           = var.project_id
  location          = var.region
  name              = "advance-canary"
  delivery_pipeline = google_clouddeploy_delivery_pipeline.quote.name
  service_account   = google_service_account.sa["csd-deploy"].email
  description       = "Advance prod canary phases after a 60s soak"

  selector {
    targets {
      id = google_clouddeploy_target.t["prod"].name
    }
  }
  rules {
    advance_rollout_rule {
      id            = "advance-after-soak"
      wait          = "60s"
      source_phases = ["canary-25", "canary-50"]
    }
  }
}
