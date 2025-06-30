# CloudRun - Dynamic Scaling demo

## Terraform Configuration Details
This Terraform configuration will:

1. Deploy a Simple Python Flask Application to Cloud Run: This will be our web container. It's a minimal app that just returns "Hello, Cloud Run!".

2. Set up a Cloud Monitoring Custom Dashboard: This dashboard will visualize the instance_count and request_count metrics for your Cloud Run service, providing the near real-time scaling visualization.

3. Provide a Google Compute Engine Instance (Optional, but Recommended for Load Generation): This VM will be a good place to run your load testing tool (Apache Bench in this case).

## How to use this Terraform Code 
Got it. Let's create the Terraform code for a Cloud Run scaling demo.

This Terraform configuration will:

Deploy a Simple Python Flask Application to Cloud Run: This will be our web container. It's a minimal app that just returns "Hello, Cloud Run!".

Set up a Cloud Monitoring Custom Dashboard: This dashboard will visualize the instance_count and request_count metrics for your Cloud Run service, providing the near real-time scaling visualization.

Provide a Google Compute Engine Instance (Optional, but Recommended for Load Generation): This VM will be a good place to run your load testing tool (Apache Bench or Nighthawk).

Terraform Code for Cloud Run Scaling Demo
1. main.tf (Core Infrastructure)

Terraform

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
      min_instance_count    = 0  # Crucial for observing cold starts and scaling from zero
      max_instance_count    = var.cloud_run_max_instances # Set a reasonable max to observe scaling
    }
    metadata {
      annotations = {
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
  value       = google_cloud_run_service.demo_app.status[0].url
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
                  filter        = "metric.type=\"run.googleapis.com/container/instance_count\" resource.type=\"cloud_run_revision\" resource.labels.service_name=\"${google_cloud_run_service.demo_app.name}\" resource.labels.location=\"${var.region}\""
                  unit          = "1"
                  minAlignmentPeriod = "60s" # Aggregate every minute
                  aligner       = "ALIGN_MEAN"
                  perSeriesAligner = "ALIGN_MEAN"
                }
                plotType = "LINE"
                legendTemplate = "Instance Count"
              },
              {
                timeSeriesQuery = {
                  filter        = "metric.type=\"run.googleapis.com/container/idle_instance_count\" resource.type=\"cloud_run_revision\" resource.labels.service_name=\"${google_cloud_run_service.demo_app.name}\" resource.labels.location=\"${var.region}\""
                  unit          = "1"
                  minAlignmentPeriod = "60s" # Aggregate every minute
                  aligner       = "ALIGN_MEAN"
                  perSeriesAligner = "ALIGN_MEAN"
                }
                plotType = "LINE"
                legendTemplate = "Idle Instance Count"
              }
            ]
            timeshiftDuration = "0s"
            yAxis = {
              label = "Instance Count"
              scale = "LINEAR"
            }
          }
        },
        {
          title = "Cloud Run Request Count"
          xyChart = {
            dataSets = [
              {
                timeSeriesQuery = {
                  filter        = "metric.type=\"run.googleapis.com/request_count\" resource.type=\"cloud_run_revision\" resource.labels.service_name=\"${google_cloud_run_service.demo_app.name}\" resource.labels.location=\"${var.region}\""
                  unit          = "1"
                  minAlignmentPeriod = "60s" # Aggregate every minute
                  aligner       = "ALIGN_RATE" # Use ALIGN_RATE to see requests per second/minute
                  perSeriesAligner = "ALIGN_RATE"
                }
                plotType = "LINE"
                legendTemplate = "Requests per minute" # Adjust based on alignment period
              }
            ]
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
  value       = "https://console.cloud.google.com/monitoring/dashboards/builder/${google_monitoring_dashboard.cloud_run_scaling_dashboard.dashboard_id}?project=${var.project_id}"
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
2. variables.tf (Configuration Variables)

Terraform

# variables.tf

variable "project_id" {
  description = "Your Google Cloud Project ID"
  type        = string
}

variable "region" {
  description = "The Google Cloud region to deploy resources"
  type        = string
  default     = "us-central1" # Or your preferred region
}

variable "cloud_run_service_name" {
  description = "Name for the Cloud Run service"
  type        = string
  default     = "cloud-run-scaling-demo"
}

variable "cloud_run_max_instances" {
  description = "Maximum number of instances for Cloud Run service"
  type        = number
  default     = 10 # Start with a lower number to clearly see scaling
}

variable "create_load_generator_vm" {
  description = "Set to true to create a Compute Engine VM for load generation"
  type        = bool
  default     = true
}

variable "load_generator_machine_type" {
  description = "Machine type for the load generator VM"
  type        = string
  default     = "e2-medium" # Adjust based on expected load
}
3. terraform.tfvars (Sensitive/Specific Values)

Create this file and fill in your actual project ID.

Terraform

# terraform.tfvars

project_id = "your-gcp-project-id" # <--- IMPORTANT: Replace with your actual project ID
# region = "europe-west1" # Uncomment and change if you prefer a different region
How to Use This Terraform Code:
1. Prerequisites:

Google Cloud SDK (gcloud CLI): Make sure it's installed and authenticated (gcloud auth login, gcloud config set project YOUR_PROJECT_ID).

- Terraform: Install Terraform on your machine.

- Permissions: Your GCP service account or user needs the following roles:

    - roles/owner (simplest for a demo, but grant specific roles for production):

    - roles/cloudrun.admin

    - roles/iam.serviceAccountUser (to allow Cloud Run to use the default service account)

    - roles/monitoring.dashboardEditor

    - roles/compute.admin (if creating the load generator VM)

    - roles/editor might also work for most.
2. Steps
- Initilize Terraform 
    `terraform init`
- Modify terraform.tfvars and update the value for variables project_id & region to match your project id & region where the resources should be created
- Review the plan
    `terraform plan`
    Carefully review the resources to be created
- Apply the Configuration
    `terraform apply`
    
    Optionally to store the output variables values for reference later on redirect the output to a text file
    `terraform apply -auto-approve > terraform_apply_output.txt`

3. After Deployment
Terraform will output the * *cloud_run_service_url* * and * *monitoring_dashboard_url* *

- Open the Cloud Monitoring Dashboard: 
    Go to the * *monitoring_dashboard_url* *in your browser. This is where you'll visualize the scaling. Set the refresh rate of the dashboard to the lowest possible (e.g., 5 seconds) to see updates quicker.

- Access the Load Generator VM (if created):
```
gcloud compute ssh cloud-run-load-generator --zone=<YOUR_REGION>-a --project=<YOUR_PROJECT_ID>
``` 
Replace <YOUR_REGION> and <YOUR_PROJECT_ID> with your actual values.

4. Generate Load and Observe Scaling:

Once connected to the load generator VM (or from your local machine with ab installed):

Start with a low load:
`ab -n 1000 -c 10 <YOUR_CLOUD_RUN_SERVICE_URL>`
(e.g., 1000 requests, 10 concurrent requests)

Gradually increase the load:
` ab -n 10000 -c 100 <YOUR_CLOUD_RUN_SERVICE_URL>`
(e.g., 10,000 requests, 100 concurrent requests)

Optional - Push the limits:
`ab -n 50000 -c 500 <YOUR_CLOUD_RUN_SERVICE_URL>`
(e.g., 50,000 requests, 100 concurrent requests)

Observe the Cloud Monitoring dashboard. You should see the "Cloud Run Request Count" spike and then the "Cloud Run Instance Count" graph showing more instances being brought online.

5. Stop the load: After running the ab commands, stop generating new requests. You should then see the request_count drop, and after a short period (due to Cloud Run's idle instance management), the instance_count will gradually decrease, eventually returning to 0 (if min_instance_count = 0).

6. Clean Up:
When you're done with the demo, destroy the resources to avoid incurring costs:
`terraform destroy`
Type * *yes* * when prompted.