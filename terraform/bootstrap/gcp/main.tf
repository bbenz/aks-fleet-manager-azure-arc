resource "google_storage_bucket" "state" {
  count = var.create_state_backend ? 1 : 0

  # GCS bucket names are globally unique across all of GCP - hence the
  # required state_storage_suffix.
  name     = "${var.name_prefix}-${var.environment}-tfstate-${var.state_storage_suffix}"
  project  = var.gcp_project_id
  location = var.gcp_region

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  labels = {
    project    = "fleet-arc-demo"
    managed_by = "terraform-bootstrap"
  }
}
