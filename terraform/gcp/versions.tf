terraform {
  required_version = ">= 1.9.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 7.39.0, < 8.0.0"
    }
  }

  # No backend block - local state by default for this demo, matching the
  # azure/ and aws/ roots. See terraform/bootstrap/README.md for documented
  # remote-state migration options.
}
