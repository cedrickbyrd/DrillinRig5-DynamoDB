output "dynamodb_table_name" {
  description = "Name of the deployed DynamoDB table."
  value       = aws_dynamodb_table.inventory.name
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for low inventory alerts."
  value       = aws_sns_topic.low_inventory_alerts.arn
}

output "inventory_checker_lambda_function_name" {
  description = "Name of the Inventory Checker Lambda function."
  value       = aws_lambda_function.inventory_checker_notifier.function_name
}

output "s3_upload_bucket_name" {
  description = "Name of the S3 bucket for inventory uploads (if enabled)."
  value       = var.enable_s3_loader ? aws_s3_bucket.inventory_uploads.bucket : "S3 Loader not enabled."
}

output "s3_to_dynamodb_loader_lambda_function_name" {
  description = "Name of the S3 to DynamoDB Loader Lambda function (if enabled)."
  value       = var.enable_s3_loader ? aws_lambda_function.s3_to_dynamodb_loader[0].function_name : "S3 Loader not enabled."
}

output "sns_subscription_confirmation_note" {
  description = "Important: Check your email for a subscription confirmation link from AWS SNS to activate alerts."
  value       = "Please confirm the SNS subscription by clicking the link in the email sent to ${var.notification_email}."
}
