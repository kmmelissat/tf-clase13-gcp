terraform {
  required_version = ">= 1.9"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "8.1.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_service_account" "runtime" {
  account_id   = "tf-state-runtime"
  display_name = "Identidad de ejecución de la clase 13"
}

resource "google_cloud_run_v2_service" "api" {
  name                = "tf-state-api"
  location            = var.region
  deletion_protection = false
  description         = "Servicio administrado con Terraform"

  template {
    service_account = google_service_account.runtime.email

    containers {
      image = "us-docker.pkg.dev/cloudrun/container/hello"
    }
  }
}
