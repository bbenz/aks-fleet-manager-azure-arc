data "google_project" "current" {
  project_id = var.project_id
}

# Fails fast (before creating anything) if the active credentials (direct or
# impersonated) cannot read the target project - cheap insurance against a
# stale `gcloud auth application-default login` session or a typo'd
# project_id.
check "expected_gcp_project" {
  assert {
    condition     = data.google_project.current.project_id == var.project_id
    error_message = "Active GCP credentials could not resolve project ${var.project_id}. Run `gcloud auth application-default login` and confirm var.project_id / var.gcp_impersonate_service_account."
  }
}

locals {
  name_base = "${var.name_prefix}-${var.environment}"

  # GCP labels only allow lowercase letters, digits, underscores and dashes
  # (63 chars max) - unlike `owner`, which is commonly an email address.
  # Sanitize once here for reuse on every labeled resource below.
  owner_label = substr(replace(lower(var.owner), "/[^a-z0-9_-]/", "-"), 0, 63)

  labels = {
    owner       = local.owner_label
    project     = var.project
    environment = var.environment
    demo        = "fleet-arc-online-boutique"
    managed_by  = "terraform"
    cloud       = "gcp"
  }

  required_apis = toset([
    "container.googleapis.com",
    "compute.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "logging.googleapis.com",
    "monitoring.googleapis.com",
  ])
}

# =============================================================================
# Required APIs
# =============================================================================
resource "google_project_service" "required" {
  for_each = local.required_apis

  project = var.project_id
  service = each.value

  disable_dependent_services = false

  # Never disable shared-project APIs on destroy - other workloads/teams in
  # this project may depend on them staying enabled. Same rationale as the
  # deliberately-not-Terraform-managed Azure resource providers in
  # terraform/azure/main.tf.
  disable_on_destroy = false
}

# =============================================================================
# Networking - custom VPC-native network. Deliberately NOT the default
# auto-mode VPC, which ships permissive pre-created firewall rules. VPC-native
# (alias IP) is the current default/required mode for new GKE clusters.
# =============================================================================
resource "google_compute_network" "demo" {
  project                 = var.project_id
  name                    = "${local.name_base}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "demo" {
  project       = var.project_id
  name          = "${local.name_base}-subnet"
  region        = var.region
  network       = google_compute_network.demo.id
  ip_cidr_range = var.subnet_cidr

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = var.pods_cidr
  }

  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = var.services_cidr
  }
}

# GCP's external passthrough Network Load Balancer health checks originate
# from these two documented ranges. Required or the frontend-external
# Service's NLB will never report healthy backends. A custom VPC (unlike the
# default auto-mode VPC) does not get this rule automatically.
resource "google_compute_firewall" "allow_lb_health_check" {
  project = var.project_id
  name    = "${local.name_base}-allow-lb-health-check"
  network = google_compute_network.demo.id

  direction = "INGRESS"

  allow {
    protocol = "tcp"
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
}

# Custom VPCs don't get the auto-mode VPC's implicit allow-internal rule -
# add it back explicitly, scoped to this VPC's own ranges only.
resource "google_compute_firewall" "allow_internal" {
  project = var.project_id
  name    = "${local.name_base}-allow-internal"
  network = google_compute_network.demo.id

  direction = "INGRESS"

  allow {
    protocol = "tcp"
  }
  allow {
    protocol = "udp"
  }
  allow {
    protocol = "icmp"
  }

  source_ranges = [var.subnet_cidr, var.pods_cidr, var.services_cidr]
}

# =============================================================================
# Node service account - deliberately NOT the default Compute Engine service
# account (which carries the broad, project-wide roles/editor). Google's own
# GKE hardening guide states the minimum viable role for a custom node SA is
# roles/container.defaultNodeServiceAccount.
# =============================================================================
resource "google_service_account" "gke_node" {
  project      = var.project_id
  account_id   = "${local.name_base}-gke-node"
  display_name = "GKE node service account for ${local.name_base}"
}

resource "google_project_iam_member" "gke_node_default" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.gke_node.email}"
}

# =============================================================================
# GKE Standard, zonal cluster. Zonal (single control-plane replica) rather
# than regional (3 replicas) - GCP's free-tier control-plane credit covers
# exactly one zonal Standard cluster, keeping this demo's Google Cloud
# control-plane cost near-zero. See docs/ARCHITECTURE.md cost section.
# =============================================================================
resource "google_container_cluster" "demo" {
  project  = var.project_id
  name     = "${local.name_base}-gke"
  location = var.zone

  # Provider default is to block destroy. Demo-friendly override - set to
  # true for anything longer-lived than this demo.
  deletion_protection = false

  # Recommended pattern: create the smallest possible default node pool and
  # immediately remove it, then manage the real node pool as its own
  # resource (google_container_node_pool.demo below) so it can be resized or
  # replaced without recreating the whole cluster.
  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.demo.id
  subnetwork      = google_compute_subnetwork.demo.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  release_channel {
    channel = var.release_channel
  }

  # Not consumed by this demo's workload, but enabling it is free and is a
  # documented GKE security best practice for any future least-privilege
  # pod-level identity needs.
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  logging_service    = "logging.googleapis.com/kubernetes"
  monitoring_service = "monitoring.googleapis.com/kubernetes"

  resource_labels = local.labels

  depends_on = [
    google_project_service.required,
    google_compute_firewall.allow_lb_health_check,
    google_compute_firewall.allow_internal,
  ]
}

resource "google_container_node_pool" "demo" {
  project  = var.project_id
  name     = "${local.name_base}-nodes"
  location = var.zone
  cluster  = google_container_cluster.demo.name

  autoscaling {
    min_node_count = var.node_min_count
    max_node_count = var.node_max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type    = var.machine_type
    disk_type       = var.disk_type
    disk_size_gb    = var.disk_size_gb
    service_account = google_service_account.gke_node.email

    # Broad cloud-platform OAuth scope is intentional here - the actual
    # permission boundary is enforced by the node SA's IAM roles above, not
    # by scopes. This is Google's own documented recommendation.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    labels = {
      cloud = "gcp"
    }

    resource_labels = local.labels

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  depends_on = [google_project_iam_member.gke_node_default]
}
