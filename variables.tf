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