# Thin, resource-free composition root. Its only job is to read
# already-applied outputs from the three independent cloud roots
# (terraform/azure, terraform/aws, terraform/gcp) and re-expose them as one
# unified set of outputs - kubeconfig commands, cluster identifiers, Fleet
# ID - so scripts/*.ps1 and docs/DEMO-RUNSHEET.md have a single place to
# look instead of three. It never manages any resources itself and never
# calls out to Azure, AWS, or GCP - `terraform apply` here only reads
# local files.
#
# Each cloud root is applied (or not) completely independently; this root
# does not require all three to exist. `terraform_remote_state` hard-errors
# ("Unable to find remote state") if its local state file doesn't exist at
# all - that's a data-source-read failure, not something try() can catch -
# so each data source below is count-gated on fileexists() to skip it
# entirely until that cloud has been applied at least once. outputs.tf then
# wraps every attribute access in try() as a second layer, to also handle
# the (rarer) case of a state file that exists but predates a given output
# being added.

data "terraform_remote_state" "azure" {
  count   = fileexists(var.azure_state_path) ? 1 : 0
  backend = "local"
  config = {
    path = var.azure_state_path
  }
}

data "terraform_remote_state" "aws" {
  count   = fileexists(var.aws_state_path) ? 1 : 0
  backend = "local"
  config = {
    path = var.aws_state_path
  }
}

data "terraform_remote_state" "gcp" {
  count   = fileexists(var.gcp_state_path) ? 1 : 0
  backend = "local"
  config = {
    path = var.gcp_state_path
  }
}
