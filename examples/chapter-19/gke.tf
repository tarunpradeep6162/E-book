terraform {
  required_version = ">= 1.10.0, < 2.0.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0" # Commit the reviewed provider selection.
    }
  }
}
variable "project_id" { type = string }
provider "google" {
  project = var.project_id
  region  = "asia-south1"
}
resource "google_compute_network" "platform" {
  name                    = "orders-platform"
  auto_create_subnetworks = false
}
resource "google_compute_subnetwork" "platform" {
  name                     = "orders-platform"
  region                   = "asia-south1"
  network                  = google_compute_network.platform.id
  ip_cidr_range            = "10.90.0.0/20"
  private_ip_google_access = true
  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.92.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.93.0.0/20"
  }
}
resource "google_container_cluster" "platform" {
  name             = "orders-autopilot"
  location         = "asia-south1"
  enable_autopilot = true
  network          = google_compute_network.platform.id
  subnetwork       = google_compute_subnetwork.platform.id
  deletion_protection = true

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = true
    master_ipv4_cidr_block  = "172.20.0.0/28"
  }
  release_channel {
    channel = "REGULAR"
  }
}
