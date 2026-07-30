output "cluster_name" {
  description = "GKE cluster name."
  value       = google_container_cluster.demo.name
}

output "cluster_location" {
  description = "GKE cluster location (zone)."
  value       = google_container_cluster.demo.location
}

output "cluster_endpoint" {
  description = "GKE cluster API server endpoint (IP only - no https:// scheme)."
  value       = google_container_cluster.demo.endpoint
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA certificate (sensitive - written to state, not printed by default)."
  value       = google_container_cluster.demo.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "project_id" {
  description = "GCP project ID used for all resources in this root."
  value       = var.project_id
}

output "region" {
  description = "GCP region used for the VPC subnet."
  value       = var.region
}

output "zone" {
  description = "GCP zone used for the GKE cluster and node pool."
  value       = var.zone
}

output "network_name" {
  description = "VPC network name."
  value       = google_compute_network.demo.name
}

output "node_service_account_email" {
  description = "Email of the least-privilege service account attached to GKE nodes."
  value       = google_service_account.gke_node.email
}

output "kubeconfig_command" {
  description = "Command to fetch this cluster's kubeconfig. gcloud names the context gke_<project>_<zone>_<cluster> automatically - see kubeconfig_rename_context_command to rename it to the repo-wide 'gke-demo' convention. Not run automatically by Terraform - scripts/04-apply.ps1 runs it after apply."
  value       = "gcloud container clusters get-credentials ${google_container_cluster.demo.name} --zone ${var.zone} --project ${var.project_id}"
}

output "kubeconfig_rename_context_command" {
  description = "Renames gcloud's auto-generated kubeconfig context to the repo-wide 'gke-demo' convention used by all scripts."
  value       = "kubectl config rename-context gke_${var.project_id}_${var.zone}_${google_container_cluster.demo.name} gke-demo"
}

output "connectedk8s_connect_command" {
  description = "Command scripts/05-connect-arc.ps1 runs to Arc-enable this cluster (requires the Azure CLI, an active az login, and the gke-demo kubeconfig context above to already exist and have cluster-admin)."
  value       = "az connectedk8s connect --name <arc-cluster-name> --resource-group <arc-resource-group> --kube-context gke-demo"
}
