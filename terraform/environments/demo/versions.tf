terraform {
  required_version = ">= 1.9.0"

  # This root intentionally declares NO provider requirements. It only
  # reads already-applied Terraform state from the azure/aws/gcp roots via
  # the built-in `terraform_remote_state` data source (backend = "local"),
  # so it never needs cloud credentials of its own - see main.tf.
}
