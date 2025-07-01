# main.tf

provider "google" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------------------------
# Cloud Run Service
# -----------------------------------------------------------------------------

resource "google_cloud_run_service" "demo_app" {
  name     = var.cloud_run_service_name
  location = var.region

  template {
    spec {
      containers {
        image = "us-docker.pkg.dev/cloudrun/container/hello" # A simple pre-built "hello world" image
        # Or build your own image and push to Artifact Registry:
        # image = "YOUR_REGION-docker.pkg.dev/YOUR_PROJECT_ID/YOUR_REPO/YOUR_IMAGE_NAME:latest"
      }
      # Configure scaling parameters
      container_concurrency = 80 # Default is 80, can be adjusted
      #min_instance_count    = 0  # Crucial for observing cold starts and scaling from zero
      #max_instance_count    = var.cloud_run_max_instances # Set a reasonable max to observe scaling
    }
    metadata {
      annotations = {
        "autoscaling.knative.dev/maxScale"      = "10"
        "autoscaling.knative.dev/minScale"      = "0"
        # Enable CPU always allocated if you want to avoid CPU throttling when idle
        # "autoscaling.knative.dev/cpu-throttling" : "false"
      }
    }
  }

  traffic {
    percent         = 100
    latest_revision = true
  }

  autogenerate_revision_name = true
}

# Allow unauthenticated access to the Cloud Run service
resource "google_cloud_run_service_iam_member" "demo_app_public_access" {
  service  = google_cloud_run_service.demo_app.name
  location = google_cloud_run_service.demo_app.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "cloud_run_service_url" {
  description = "The URL of the deployed Cloud Run service"
  value       = "${google_cloud_run_service.demo_app.status[0].url}/"
}

# -----------------------------------------------------------------------------
# Cloud Monitoring Dashboard for Visualization
# -----------------------------------------------------------------------------

resource "google_monitoring_dashboard" "cloud_run_scaling_dashboard" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "Cloud Run Scaling Demo - ${var.cloud_run_service_name}"
    gridLayout = {
      columns = "2"
      widgets = [
        {
          title = "Cloud Run Instance Count"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  "timeSeriesFilter": {
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": [
                        "resource.label.\"service_name\"",
                        "metric.label.\"state\""
                      ],
                      "perSeriesAligner": "ALIGN_MAX"
                    },
                    "filter": "metric.type=\"run.googleapis.com/container/instance_count\" resource.type=\"cloud_run_revision\" resource.label.\"location\"=\"${var.region}\" resource.label.\"project_id\"=\"${var.project_id}\" resource.label.\"service_name\"=\"${google_cloud_run_service.demo_app.name}\""
                  },
                  "unitOverride": ""

                }
                plotType = "LINE"
                legendTemplate = "$${metric.labels.state}"
              }],
              "thresholds": [],
              "yAxis": {
                "label": "",
                "scale": "LINEAR"
              }
            }

          },
          {
            title = "Cloud Run Request Count"
            xyChart = {
              dataSets = [
              {
                timeSeriesQuery = {
                   "timeSeriesFilter": {
                    "aggregation": {
                      "alignmentPeriod": "60s",
                      "crossSeriesReducer": "REDUCE_SUM",
                      "groupByFields": [
                        "metric.label.\"response_code_class\""
                      ],
                      "perSeriesAligner": "ALIGN_RATE"
                    },
                    filter        = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.labels.service_name=\"${google_cloud_run_service.demo_app.name}\" resource.labels.location=\"${var.region}\""
                   },
                  "unitOverride": "1"
                }
                plotType = "LINE"
                legendTemplate = "$${metric.labels.response_code_class}" # Adjust based on alignment period
              }
              ],
            timeshiftDuration = "0s"
            yAxis = {
              label = "Requests"
              scale = "LINEAR"
            }
          }
        }
      ]
    }
  })
}

output "monitoring_dashboard_url" {
  description = "URL to the Cloud Monitoring dashboard"
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${element(split("/", google_monitoring_dashboard.cloud_run_scaling_dashboard.id), 3)}" 
 }


# -----------------------------------------------------------------------------
# Google Compute Engine Instance for Load Generation (Optional)
# -----------------------------------------------------------------------------

resource "google_compute_network" "vpc_network" {
  name = "cloud-run-demo-vpc"
  auto_create_subnetworks = true
}

resource "google_compute_firewall" "allow_ssh_http" {
  name    = "allow-ssh-http-to-load-gen"
  network = google_compute_network.vpc_network.name

  allow {
    protocol = "tcp"
    ports    = ["22", "80", "443"] # Allow SSH for management, and HTTP/S if you host a web tool
  }

  source_ranges = ["0.0.0.0/0"] # Be cautious: allow from anywhere. Restrict in production.
  target_tags   = ["load-generator"]
}

resource "google_compute_instance" "load_generator" {
  count        = var.create_load_generator_vm ? 1 : 0
  name         = "cloud-run-load-generator"
  machine_type = var.load_generator_machine_type
  zone         = "${var.region}-a" # Using a specific zone within the region

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-11"
    }
  }

  network_interface {
    network = google_compute_network.vpc_network.name
    access_config {} # Assigns an ephemeral public IP
  }

  tags = ["load-generator"]

  metadata_startup_script = <<-EOF
    #!/bin/bash
    sudo apt-get update
    sudo apt-get install -y apache2-utils # For 'ab' (Apache Bench)
    # sudo apt-get install -y nighthawk # Nighthawk setup is more involved, requires specific builds or Docker
    echo "Load generator VM ready. SSH to this VM and use 'ab' to test Cloud Run URL."
  EOF

  lifecycle {
    ignore_changes = [metadata_startup_script] # Avoid re-running startup script on every apply
  }
}

output "load_generator_external_ip" {
  description = "External IP address of the load generator VM (if created)"
  value       = var.create_load_generator_vm ? google_compute_instance.load_generator[0].network_interface[0].access_config[0].nat_ip : "N/A"
}