# Auth model (see docs/AUTHENTICATION-AND-PERMISSIONS.md for full detail):
#
#   1. A human runs `gcloud auth application-default login` once
#      (scripts/00-bootstrap-auth.ps1 checks/prompts for this). This is a
#      browser-interactive, MFA-capable login - never a JSON service-account
#      key on disk.
#   2. By default (gcp_impersonate_service_account left null) Terraform uses
#      that human identity directly. The human's own account needs the
#      elevated roles listed in docs/AUTHENTICATION-AND-PERMISSIONS.md for
#      the duration of the apply - remove them afterwards.
#   3. Optionally, once a "terraform-runner" service account has been
#      manually bootstrapped (one-time, outside this root - see
#      docs/AUTHENTICATION-AND-PERMISSIONS.md) and the human has been granted
#      roles/iam.serviceAccountTokenCreator on it, set
#      gcp_impersonate_service_account so Terraform impersonates that
#      least-privilege identity instead.
provider "google" {
  project = var.project_id
  region  = var.region

  impersonate_service_account = var.gcp_impersonate_service_account
}
