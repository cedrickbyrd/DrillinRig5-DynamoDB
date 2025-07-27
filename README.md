# DrillinRig5-DynamoDB
# DrillinRig Inventory Management with AWS Serverless
# DrillinRig Inventory Management with AWS Serverless

This repository contains Terraform configurations to deploy an inventory management system for DrillinRig.
It uses AWS DynamoDB to store inventory, AWS Lambda to monitor stock levels via DynamoDB Streams,
and AWS SNS to send email notifications when an item's quantity falls below a defined minimum.

Optionally, it includes an S3 bucket and a Lambda function for bulk initial inventory uploads.

## Architecture

* **Amazon DynamoDB:** Stores inventory items (item_id, item_name, quantity, minimum_quantity, last_notified_timestamp). DynamoDB Streams are enabled.
* **AWS Lambda (InventoryCheckerNotifier):** Triggered by DynamoDB Stream events. Checks if `quantity <= minimum_quantity`. If true and not recently notified, publishes a message to SNS.
* **Amazon SNS:** Publishes low inventory alerts. Configured with an email subscription.
* **Amazon S3 (Optional):** Bucket for uploading CSV files for bulk inventory loading.
* **AWS Lambda (S3ToDynamoDBLoader - Optional):** Triggered by S3 object creation. Parses CSV files and loads/updates inventory into DynamoDB.

## Prerequisites

1.  **AWS Account:** You need an active AWS account.
2.  **AWS CLI Configured:** Ensure your AWS CLI is configured with credentials and a default region (`aws configure`).
3.  **Terraform:** Install Terraform (version 1.0+ recommended).
4.  **Python 3.x:** Installed on your local machine to package Lambda code.

## Setup and Deployment

1.  **Clone the repository:**
    ```bash
    git clone <your-repo-url>
    cd drillinrig-inventory-terraform
    ```

2.  **Navigate to the Terraform directory:**
    ```bash
    cd <project-root> # Where main.tf, variables.tf etc. are located
    ```

3.  **Update `variables.tf`:**
    Open `variables.tf` and set the following:
    * `notification_email`: **Crucially, change this to the email address where you want to receive alerts.**
    * `s3_upload_bucket_name`: **If `enable_s3_loader` is true, change this to a globally unique S3 bucket name.**
    * `enable_s3_loader`: Set to `true` if you want the S3 bulk upload functionality, `false` otherwise.

4.  **Initialize Terraform:**
    ```bash
    terraform init
    ```

5.  **Review the plan (highly recommended):**
    ```bash
    terraform plan
    ```
    This command will show you what resources Terraform will create, modify, or destroy. Review it carefully.

6.  **Apply the Terraform configuration:**
    ```bash
    terraform apply
    ```
    Type `yes` when prompted to confirm the deployment.

7.  **Confirm SNS Subscription:**
    After `terraform apply` completes, **check the email address you provided in `notification_email`**. You will receive an email from AWS SNS asking you to confirm your subscription. **You MUST click the confirmation link** for email notifications to work.

## Usage

### Managing Inventory

Inventory is managed directly in the DynamoDB table named `DrillinRigInventory` (or whatever you configured `dynamodb_table_name` to be).

**Attributes for each item:**

* `item_id` (String - Primary Key): Unique identifier for the item (e.g., `drill-bit-10mm`, `oil-filter-XYZ`).
* `item_name` (String): Human-readable name (e.g., `10mm Drill Bit`, `Hydraulic Oil Filter`).
* `quantity` (Number): Current stock count. When this value is updated (e.g., decremented after use), the Lambda will trigger.
* `minimum_quantity` (Number - Optional): The threshold below which an alert should be sent for *this specific item*. If not provided, `default_minimum_quantity` from `variables.tf` will be used.
* `last_notified_timestamp` (Number - Epoch time): Automatically updated by the Lambda after sending a notification to prevent spamming.

**Example DynamoDB Item (JSON):**

```json
{
  "item_id": {"S": "drill-bit-10mm"},
  "item_name": {"S": "10mm Tungsten Drill Bit"},
  "quantity": {"N": "3"},
  "minimum_quantity": {"N": "5"},
  "last_notified_timestamp": {"N": "0"}
}
