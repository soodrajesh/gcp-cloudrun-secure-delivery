# 01 · Build & teardown

```bash
gcloud config set project <project>
./scripts/up.sh            # infra -> secure build -> staging -> approve -> prod canary -> live tests
./scripts/up.sh --plan
./scripts/up.sh --skip-tests
./scripts/down.sh          # --purge also removes this repo's state
```
`down.sh` deletes the Cloud Run services and the delivery pipeline's releases (created by Cloud Deploy, outside Terraform state) before `terraform destroy`. Destroying this stack sets the **project's** Binary Authorization policy back to allow-all — it is a single project-wide resource, not scoped to this repo.
