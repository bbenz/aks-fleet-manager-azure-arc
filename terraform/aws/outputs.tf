output "cluster_name" {
  description = "EKS cluster name."
  value       = aws_eks_cluster.demo.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint."
  value       = aws_eks_cluster.demo.endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded cluster CA certificate (sensitive - written to state, not printed by default)."
  value       = aws_eks_cluster.demo.certificate_authority[0].data
  sensitive   = true
}

output "region" {
  description = "AWS region used for all resources in this root."
  value       = var.region
}

output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.demo.id
}

output "public_subnet_ids" {
  description = "Public subnet IDs (nodes and NLB both live here - see main.tf networking comment)."
  value       = aws_subnet.public[*].id
}

output "oidc_provider_arn" {
  description = "IAM OIDC provider ARN for this cluster (empty if enable_aws_load_balancer_controller = false)."
  value       = var.enable_aws_load_balancer_controller ? aws_iam_openid_connect_provider.eks[0].arn : null
}

output "node_role_arn" {
  description = "IAM role ARN used by EKS managed node group instances."
  value       = aws_iam_role.node.arn
}

output "account_id" {
  description = "AWS account ID resolved from the active credentials used to apply."
  value       = data.aws_caller_identity.current.account_id
}

output "kubeconfig_command" {
  description = "Command to fetch this cluster's kubeconfig into the fleet-arc-demo-wide 'eks-demo' context. Not run automatically by Terraform - scripts/04-apply.ps1 runs it after apply."
  value       = "aws eks update-kubeconfig --name ${aws_eks_cluster.demo.name} --region ${var.region} --alias eks-demo${var.aws_profile != null ? " --profile ${var.aws_profile}" : ""}"
}

output "connectedk8s_connect_command" {
  description = "Command scripts/05-connect-arc.ps1 runs to Arc-enable this cluster (requires the Azure CLI, an active az login, and the eks-demo kubeconfig context above to already exist and have cluster-admin)."
  value       = "az connectedk8s connect --name <arc-cluster-name> --resource-group <arc-resource-group> --kube-context eks-demo"
}
