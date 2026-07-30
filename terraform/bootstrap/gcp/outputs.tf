locals {
  backend_snippet = <<-EOT
    terraform {
      backend "gcs" {
        bucket = "${var.create_state_backend ? google_storage_bucket.state[0].name : ""}"
        prefix = "gcp"
      }
    }
  EOT
}

output "state_backend_config" {
  description = "Ready-to-paste gcs backend block for terraform/gcp/versions.tf, once create_state_backend = true has been applied."
  value       = var.create_state_backend ? local.backend_snippet : "create_state_backend is false - no backend created. This demo uses local state; see ../README.md."
}
