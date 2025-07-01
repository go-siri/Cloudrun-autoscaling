# CloudRun - Dynamic Scaling demo

## Terraform Configuration Details
This Terraform configuration will:

1. Deploy a Simple Python Flask Application to Cloud Run: This will be our web container. It's a minimal app that just returns "Hello, Cloud Run!".

2. Set up a Cloud Monitoring Custom Dashboard: This dashboard will visualize the instance_count and request_count metrics for your Cloud Run service, providing the near real-time scaling visualization.

3. Provide a Google Compute Engine Instance (Optional, but Recommended for Load Generation): This VM will be a good place to run your load testing tool (Apache Bench in this case).

## How to use this Terraform Code 
The Terraform code in this repo deploys Cloud Run configuration to showcase autoscaling feature.

### Terraform configuration 

1. Deploy a Simple Python Flask Application to Cloud Run: This will be our web container. It's a minimal app that just returns "Hello, Cloud Run!".

2. Set up a Cloud Monitoring Custom Dashboard: This dashboard will visualize the instance_count and request_count metrics for your Cloud Run service, providing the near real-time scaling visualization.

3. Provide a Google Compute Engine Instance (Optional, but Recommended for Load Generation): This VM will be a good place to run your load testing tool (Apache Bench or Nighthawk).


### How to Use This Terraform Code
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
    - Initilize Terraform. 
            ```terraform init```
    - Modify * *terraform.tfvars* * and update the value for variables project_id & region to match your project id & region where the resources should be created
    - Review the plan. 
            ```terraform plan```
    Carefully review the resources to be created
    - Apply the Configuration. 
            ```terraform apply```
       (optinal) To avoid the prompt during apply and store output in a file, you can use  
            ```terraform apply -auto-approve > terraform_apply_output.txt```

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

    - Start with a low load:    
        `ab -n 1000 -c 10 <YOUR_CLOUD_RUN_SERVICE_URL>`. 
      (e.g., 1000 requests, 10 concurrent requests)

    - Gradually increase the load:  
        ` ab -n 10000 -c 100 <YOUR_CLOUD_RUN_SERVICE_URL>`. 
      (e.g., 10,000 requests, 100 concurrent requests)

    - Push the limits:  
        `ab -n 50000 -c 500 <YOUR_CLOUD_RUN_SERVICE_URL>`. 
      (e.g., 50,000 requests, 100 concurrent requests)

    Observe the Cloud Monitoring dashboard. You should see the "Cloud Run Request Count" spike and then the "Cloud Run Instance Count" graph showing more instances being brought online.

5. Stop the load
   After running the ab commands, stop generating new requests. You should then see the request_count drop, and after a short period (due to Cloud Run's idle instance management), the instance_count will gradually decrease, eventually returning to 0 (if min_instance_count = 0).

### Clean Up
When you're done with the demo, destroy the resources to avoid incurring costs:
`terraform destroy`
Type * *yes* * when prompted.