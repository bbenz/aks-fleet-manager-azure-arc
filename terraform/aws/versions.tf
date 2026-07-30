# AWS root: VPC (2 public subnets, no NAT gateway - see main.tf comment),
# EKS cluster + managed node group, least-privilege IAM via EKS access
# entries (not legacy aws-auth ConfigMap), and the AWS Load Balancer
# Controller (current, non-deprecated path to a Network Load Balancer for
# the frontend Service - see main.tf comment on why a plain
# `type: LoadBalancer` Service without LBC installed is avoided).
#
# Arc-connecting this cluster to Azure and joining it to the Fleet happens
# imperatively via scripts/05-connect-arc.ps1 and scripts/06-join-fleet.ps1
# AFTER this root is applied - not part of this Terraform root.
terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.54.0, < 7.0.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 3.2.0, < 4.0.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.2.0, < 4.0.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0.0, < 5.0.0"
    }
  }

  # Local state by default for this demo repo. See docs/OPERATIONS.md for the
  # three documented remote-state migration strategies and the optional
  # terraform/bootstrap/ root if you choose to adopt remote state instead.
  # backend "s3" {}
}
