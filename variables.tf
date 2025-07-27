variable "aws_region" {
  description = "The AWS region to deploy resources into."
  type        = string
  default     = "us-east-1" # Or your preferred region
}

variable "project_name" {
  description = "A unique prefix for naming resources."
  type        = string
  default     = "DrillinRigInventory"
}

variable "environment" {
  description = "The deployment environment (e.g., dev, prod)."
  type        = string
  default     = "dev"
}

variable "dynamodb_table_name" {
  description = "Name for the DynamoDB inventory table."
  type        = string
  default     = "DrillinRigInventory"
}

variable "sns_topic_name" {
  description = "Name for the SNS topic for low inventory alerts."
  type        = string
  default     = "LowInventoryAlerts"
}

variable "notification_email" {
  description = "Email address to send low inventory notifications to. YOU MUST CONFIRM THIS SUBSCRIPTION."
  type        = string
  # IMPORTANT: Replace with the actual email address you want to use.
  # Example: default = "your_email@example.com"
}

variable "default_minimum_quantity" {
  description = "The default minimum quantity threshold for items if not specified in DynamoDB."
  type        = number
  default     = 5
}

variable "s3_upload_bucket_name" {
  description = "Name for the S3 bucket where inventory files will be uploaded (must be globally unique)."
  type        = string
  default     = "drillinrig-inventory-uploads-unique-bucket-name" # **CHANGE THIS TO A GLOBALLY UNIQUE NAME**
}

variable "enable_s3_loader" {
  description = "Set to true to deploy the S3-to-DynamoDB loader Lambda and S3 bucket."
  type        = bool
  default     = true # Set to true if you need the S3 bulk upload functionality
}
