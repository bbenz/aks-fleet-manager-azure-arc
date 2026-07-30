provider "google" {
  project = var.gcp_project_id
  region  = var.gcp_region

  impersonate_service_account = var.gcp_impersonate_service_account
}
