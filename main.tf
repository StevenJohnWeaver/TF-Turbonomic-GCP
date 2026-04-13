terraform {
  required_providers {
    turbonomic = {
      source  = "IBM/turbonomic"
      version = "1.9.0"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "turbonomic" {
  hostname   = var.turbo_hostname
  username   = var.turbo_username
  password   = var.turbo_password
  skipverify = true
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  zone    = var.gcp_zone
}

variable "turbo_username" {
  description = "The username for the Turbonomic instance"
  type        = string
  sensitive   = false
}

variable "turbo_password" {
  description = "The password for the Turbonomic instance"
  type        = string
  sensitive   = true
}

variable "turbo_hostname" {
  description = "The hostname for the Turbonomic instance"
  type        = string
  sensitive   = false
}

variable "gcp_project" {
  description = "The GCP project ID"
  type        = string
}

variable "gcp_region" {
  description = "The GCP region to deploy resources in"
  type        = string
  default     = "us-central1"
}

variable "gcp_zone" {
  description = "The GCP zone to deploy resources in"
  type        = string
  default     = "us-central1-a"
}

# Turbonomic queries the GCP Compute instance by name and returns the
# current machine type alongside its recommended (right-sized) machine type.
data "turbonomic_google_compute_instance" "example" {
  entity_name          = "exampleVirtualMachine"
  default_machine_type = "e2-micro"
}

resource "google_compute_instance" "terraform-demo-gce" {
  name         = "example-virtual-machine"
  machine_type = data.turbonomic_google_compute_instance.example.new_machine_type

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
    }
  }

  network_interface {
    network = "default"
    access_config {}
  }

  labels = merge(
    {
      name = "examplevirtualmachine"
    },
    provider::turbonomic::get_tag()
  )
}

check "turbonomic_consistent_with_recommendation_check" {
  assert {
    condition     = google_compute_instance.terraform-demo-gce.machine_type == coalesce(data.turbonomic_google_compute_instance.example.new_machine_type, google_compute_instance.terraform-demo-gce.machine_type)
    error_message = "Instance machine type must match Turbonomic's recommendation. Current: ${data.turbonomic_google_compute_instance.example.current_machine_type}, Recommended: ${coalesce(data.turbonomic_google_compute_instance.example.new_machine_type, google_compute_instance.terraform-demo-gce.machine_type)}"
  }
}
