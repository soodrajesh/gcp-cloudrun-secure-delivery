output "artifact_repo" { value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.apps.repository_id}" }
output "work_bucket" { value = google_storage_bucket.work.name }
output "build_sa" { value = google_service_account.sa["csd-build"].email }
output "deploy_sa" { value = google_service_account.sa["csd-deploy"].email }
output "app_sa" { value = google_service_account.sa["csd-app"].email }
output "kms_keyring" { value = google_kms_key_ring.sign.name }
output "key_versions" { value = { for k, v in data.google_kms_crypto_key_version.sign : k => v.name } }
output "pipeline" { value = google_clouddeploy_delivery_pipeline.quote.name }
