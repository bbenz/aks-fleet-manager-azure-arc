# No provider blocks needed. This root is a read-only composition layer
# over the azure/aws/gcp roots' local state files - see the
# terraform_remote_state data sources in main.tf. Kept as an (otherwise
# empty) file so this root's shape matches every other Terraform root in
# the repo: versions.tf, providers.tf, variables.tf, main.tf, outputs.tf.
