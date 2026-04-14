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
  default     = "us-east4"
}

variable "gcp_zone" {
  description = "The GCP zone to deploy resources in"
  type        = string
  default     = "us-east4-b"
}

variable "instance_name" {
  description = "The name of the GCE instance (must match the entity name in Turbonomic). Must be lowercase letters, numbers, and hyphens only."
  type        = string
  default     = "example-virtual-machine"
}

# Turbonomic queries the GCP Compute instance by name and returns the
# current machine type alongside its recommended (right-sized) machine type.
data "turbonomic_google_compute_instance" "example" {
  entity_name          = var.instance_name
  default_machine_type = "e2-standard-2"
}

# Turbonomic queries the boot disk by name and returns the recommended
# size and type. At 10 GB pd-standard, Turbo flags it quickly for
# IOPS congestion — giving us a reliable demo action.
data "turbonomic_google_compute_disk" "example" {
  entity_name  = var.instance_name
  default_type = "pd-standard"
  default_size = 10
}

# Boot disk managed as a standalone resource so Turbonomic's size
# recommendation can be applied in-place without recreating the instance.
resource "google_compute_disk" "terraform-demo-boot-disk" {
  name  = var.instance_name
  image = "debian-cloud/debian-12"
  type  = coalesce(data.turbonomic_google_compute_disk.example.new_type, "pd-standard")
  size  = coalesce(data.turbonomic_google_compute_disk.example.new_size, 10)
  zone  = var.gcp_zone

  labels = merge(
    {
      name = lower(var.instance_name)
    },
    provider::turbonomic::get_tag()
  )
}

resource "google_compute_instance" "terraform-demo-gce" {
  name         = var.instance_name
  machine_type = data.turbonomic_google_compute_instance.example.new_machine_type
  zone         = var.gcp_zone

  boot_disk {
    source = google_compute_disk.terraform-demo-boot-disk.self_link
  }

  network_interface {
    network = "default"
    access_config {}
  }

  labels = merge(
    {
      name = lower(var.instance_name)
    },
    provider::turbonomic::get_tag()
  )
}

check "turbonomic_vm_recommendation_check" {
  assert {
    condition     = google_compute_instance.terraform-demo-gce.machine_type == coalesce(data.turbonomic_google_compute_instance.example.new_machine_type, google_compute_instance.terraform-demo-gce.machine_type)
    error_message = "VM machine type must match Turbonomic's recommendation. Current: ${coalesce(data.turbonomic_google_compute_instance.example.current_machine_type, "unknown")}, Recommended: ${coalesce(data.turbonomic_google_compute_instance.example.new_machine_type, google_compute_instance.terraform-demo-gce.machine_type)}"
  }
}

check "turbonomic_disk_recommendation_check" {
  assert {
    condition     = google_compute_disk.terraform-demo-boot-disk.size == coalesce(data.turbonomic_google_compute_disk.example.new_size, google_compute_disk.terraform-demo-boot-disk.size)
    error_message = "Disk size must match Turbonomic's recommendation. Current: ${coalesce(data.turbonomic_google_compute_disk.example.current_size, google_compute_disk.terraform-demo-boot-disk.size)} GB, Recommended: ${coalesce(data.turbonomic_google_compute_disk.example.new_size, google_compute_disk.terraform-demo-boot-disk.size)} GB"
  }
}
