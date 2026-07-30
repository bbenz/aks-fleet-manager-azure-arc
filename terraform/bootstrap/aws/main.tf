# Terraform >= 1.10 supports native S3 state locking (`use_lockfile = true`
# in the consuming root's backend "s3" block) - no DynamoDB lock table
# needed for new setups. If you're pinned to Terraform < 1.10, add a
# DynamoDB lock table alongside this bucket yourself; see
# https://developer.hashicorp.com/terraform/language/backend/s3.
resource "aws_s3_bucket" "state" {
  count = var.create_state_backend ? 1 : 0

  # S3 bucket names are globally unique across all of AWS - hence the
  # required state_storage_suffix.
  bucket = "${var.name_prefix}-${var.environment}-tfstate-${var.state_storage_suffix}"

  tags = {
    project    = "fleet-arc-demo"
    managed_by = "terraform-bootstrap"
  }
}

resource "aws_s3_bucket_versioning" "state" {
  count = var.create_state_backend ? 1 : 0

  bucket = aws_s3_bucket.state[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  count = var.create_state_backend ? 1 : 0

  bucket = aws_s3_bucket.state[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  count = var.create_state_backend ? 1 : 0

  bucket                  = aws_s3_bucket.state[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
