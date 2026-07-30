# The aws provider relies on the default AWS credential provider chain
# (env vars, shared config/SSO profile, or an assumed role) - never a static
# access key in this repo. See docs/AUTHENTICATION-AND-PERMISSIONS.md.
provider "aws" {
  region  = var.region
  profile = var.aws_profile

  dynamic "assume_role" {
    for_each = var.aws_assume_role_arn != null ? [1] : []
    content {
      role_arn = var.aws_assume_role_arn
    }
  }

  default_tags {
    tags = {
      owner       = var.owner
      project     = var.project
      environment = var.environment
      demo        = "fleet-arc-online-boutique"
      managed_by  = "terraform"
      cloud       = "aws"
    }
  }
}

# The kubernetes/helm providers authenticate to the EKS cluster created by
# this same root using a short-lived, freshly-minted STS token (never a
# static kubeconfig secret). This is the standard, documented pattern for
# managing in-cluster resources (the LBC service account + Helm release) in
# the same apply that creates the cluster.
#
# NOTE: on a very first `terraform apply` from empty state, Terraform must
# create the EKS cluster before it can configure these providers. This is a
# well-known Terraform+EKS+Helm sequencing pattern; if you ever see a
# "provider configuration cannot be determined" style error on a truly first
# apply, simply re-run `terraform apply` once more - a second run always
# succeeds because the cluster then already exists in state.
provider "kubernetes" {
  host                   = aws_eks_cluster.demo.endpoint
  cluster_ca_certificate = base64decode(aws_eks_cluster.demo.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.demo.token
}

provider "helm" {
  kubernetes = {
    host                   = aws_eks_cluster.demo.endpoint
    cluster_ca_certificate = base64decode(aws_eks_cluster.demo.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.demo.token
  }
}
