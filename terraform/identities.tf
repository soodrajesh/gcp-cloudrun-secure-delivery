locals {
  sas = {
    "csd-build"  = "Cloud Build: builds, gates, pushes, attests"
    "csd-deploy" = "Cloud Deploy executor: renders and rolls out to Cloud Run"
    "csd-app"    = "Runtime identity of the quote service (no roles)"
  }
  build_member  = "serviceAccount:${google_service_account.sa["csd-build"].email}"
  deploy_member = "serviceAccount:${google_service_account.sa["csd-deploy"].email}"
}

resource "google_service_account" "sa" {
  for_each     = local.sas
  project      = var.project_id
  account_id   = each.key
  display_name = each.value
  depends_on   = [google_project_service.apis]
}

resource "google_artifact_registry_repository" "apps" {
  project       = var.project_id
  location      = var.region
  repository_id = "apps"
  format        = "DOCKER"
  docker_config {
    immutable_tags = true # a tag can never be re-pointed at different bits
  }
  depends_on = [google_project_service.apis]
}

resource "google_storage_bucket" "work" {
  project                     = var.project_id
  name                        = "${var.project_id}-csd-${random_id.this.hex}"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
  versioning {
    enabled = true
  }
}

# ── build identity: least privilege ──
resource "google_project_iam_member" "build_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.build_member
}

resource "google_artifact_registry_repository_iam_member" "build_push" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.apps.name
  role       = "roles/artifactregistry.writer"
  member     = local.build_member
}

resource "google_storage_bucket_iam_member" "build_bucket" {
  bucket = google_storage_bucket.work.name
  role   = "roles/storage.objectAdmin"
  member = local.build_member
}

# ── deploy identity: least privilege ──
resource "google_project_iam_member" "deploy" {
  for_each = toset(["roles/clouddeploy.jobRunner", "roles/clouddeploy.releaser", "roles/run.developer", "roles/logging.logWriter"])
  project  = var.project_id
  role     = each.value
  member   = local.deploy_member
}

resource "google_artifact_registry_repository_iam_member" "deploy_read" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.apps.name
  role       = "roles/artifactregistry.reader"
  member     = local.deploy_member
}

resource "google_storage_bucket_iam_member" "deploy_bucket" {
  bucket = google_storage_bucket.work.name
  role   = "roles/storage.objectAdmin"
  member = local.deploy_member
}

# the executor may deploy services that run AS csd-app, and nothing else
resource "google_service_account_iam_member" "deploy_actas_app" {
  service_account_id = google_service_account.sa["csd-app"].name
  role               = "roles/iam.serviceAccountUser"
  member             = local.deploy_member
}

resource "google_service_account_iam_member" "deploy_actas_self" {
  service_account_id = google_service_account.sa["csd-deploy"].name
  role               = "roles/iam.serviceAccountUser"
  member             = local.deploy_member
}

# the operator may run builds as csd-build and create releases as csd-deploy (no project-wide actAs)
resource "google_service_account_iam_member" "operator_actas" {
  for_each           = toset(["csd-build", "csd-deploy"])
  service_account_id = google_service_account.sa[each.key].name
  role               = "roles/iam.serviceAccountUser"
  member             = "user:${var.admin_email}"
}
