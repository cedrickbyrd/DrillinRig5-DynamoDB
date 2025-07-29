# Configure the AWS provider
provider "aws" {
  region = var.aws_region
}

# -----------------------------------------------------------------------------
# 1. DynamoDB Table
# -----------------------------------------------------------------------------
resource "aws_dynamodb_table" "inventory" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST" # On-demand capacity
  hash_key     = "item_id"

  attribute {
    name = "item_id"
    type = "S"
  }

  # Enable DynamoDB Streams
  stream_enabled   = true
  stream_view_type = "NEW_IMAGE" # We need the full item after modification

  tags = {
    Name        = "${var.project_name}-InventoryTable"
    Environment = var.environment
  }
}

# -----------------------------------------------------------------------------
# 2. SNS Topic for Low Inventory Alerts
# -----------------------------------------------------------------------------
resource "aws_sns_topic" "low_inventory_alerts" {
  name = var.sns_topic_name

  tags = {
    Name        = "${var.project_name}-LowInventoryAlerts"
    Environment = var.environment
  }
}

# SNS Topic Subscription (Email)
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.low_inventory_alerts.arn
  protocol  = "email"
  endpoint  = var.notification_email # This email will receive the alerts
  # Note: A confirmation email will be sent to this address, you must confirm it.
}

# -----------------------------------------------------------------------------
# 3. Lambda Function: Inventory Checker & Notifier
# -----------------------------------------------------------------------------

# IAM Role for Lambda Function
resource "aws_iam_role" "inventory_checker_lambda_role" {
  name = "${var.project_name}-InventoryCheckerLambdaRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-InventoryCheckerLambdaRole"
    Environment = var.environment
  }
}

# IAM Policy for Lambda Function
resource "aws_iam_policy" "inventory_checker_lambda_policy" {
  name        = "${var.project_name}-InventoryCheckerLambdaPolicy"
  description = "IAM policy for Lambda to read DynamoDB Streams and publish to SNS"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "dynamodb:DescribeStream",
          "dynamodb:GetRecords",
          "dynamodb:GetShardIterator",
          "dynamodb:ListStreams"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.inventory.stream_arn
      },
      {
        Action   = "sns:Publish",
        Effect   = "Allow",
        Resource = aws_sns_topic.low_inventory_alerts.arn
      }
    ]
  })
}

# Attach Policy to Role
resource "aws_iam_role_policy_attachment" "inventory_checker_lambda_attach" {
  role       = aws_iam_role.inventory_checker_lambda_role.name
  policy_arn = aws_iam_policy.inventory_checker_lambda_policy.arn
}

# Package Lambda code
data "archive_file" "inventory_checker_lambda_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambda/inventory_checker_notifier"
  output_path = "${path.module}/lambda/inventory_checker_notifier.zip"
}

# Lambda Function Definition
resource "aws_lambda_function" "inventory_checker_notifier" {
  function_name    = "${var.project_name}-InventoryCheckerNotifier"
  handler          = "main.lambda_handler" # File name is main.py, function is lambda_handler
  runtime          = "python3.12"          # Or latest stable Python runtime
  role             = aws_iam_role.inventory_checker_lambda_role.arn
  filename         = data.archive_file.inventory_checker_lambda_zip.output_path
  source_code_hash = data.archive_file.inventory_checker_lambda_zip.output_base64sha256
  timeout          = 30  # seconds
  memory_size      = 128 # MB

  environment {
    variables = {
      SNS_TOPIC_ARN        = aws_sns_topic.low_inventory_alerts.arn
      DEFAULT_MIN_QUANTITY = var.default_minimum_quantity # Fallback if item has no specific min_quantity
    }
  }

  tags = {
    Name        = "${var.project_name}-InventoryCheckerNotifier"
    Environment = var.environment
  }
}

# Lambda Event Source Mapping (DynamoDB Stream Trigger)
resource "aws_lambda_event_source_mapping" "inventory_stream_mapping" {
  event_source_arn                   = aws_dynamodb_table.inventory.stream_arn
  function_name                      = aws_lambda_function.inventory_checker_notifier.arn
  starting_position                  = "LATEST" # Start processing from new records
  batch_size                         = 10       # Process up to 10 records at a time
  maximum_batching_window_in_seconds = 1        # Process records as quickly as possible
  # For production, consider 'TRIM_HORIZON' for initial load or full replay
  # or ensure your function is idempotent if using 'TRIM_HORIZON'.
}


# -----------------------------------------------------------------------------
# 4. S3 Bucket for initial/bulk inventory uploads (Optional)
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "inventory_uploads" {
  bucket = var.s3_upload_bucket_name
  # Prevent accidental deletion in production
  force_destroy = false

  tags = {
    Name        = "${var.project_name}-InventoryUploads"
    Environment = var.environment
  }
}

# Block public access for the S3 bucket
resource "aws_s3_bucket_public_access_block" "inventory_uploads_public_access_block" {
  bucket = aws_s3_bucket.inventory_uploads.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# S3 Bucket Notification for Lambda (Optional)
resource "aws_s3_bucket_notification" "s3_to_dynamodb_notification" {
  count = var.enable_s3_loader ? 1 : 0 # Only create if enable_s3_loader is true

  bucket = aws_s3_bucket.inventory_uploads.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_to_dynamodb_loader[0].arn
    events              = ["s3:ObjectCreated:*"] # Trigger on any new object creation
    filter_prefix       = "uploads/"             # Only process files in the 'uploads/' prefix
    filter_suffix       = ".csv"                 # Only process .csv files
  }

  # Add explicit dependency on the Lambda permission
  depends_on = [
    aws_lambda_permission.allow_s3_to_invoke_s3_to_dynamodb_loader
  ]
}

# Allow S3 to invoke the Lambda function (Optional)
resource "aws_lambda_permission" "allow_s3_to_invoke_s3_to_dynamodb_loader" {
  count = var.enable_s3_loader ? 1 : 0

  statement_id  = "AllowS3InvokeLambda"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_to_dynamodb_loader[0].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.inventory_uploads.arn
}

# -----------------------------------------------------------------------------
# 5. Lambda Function: S3 to DynamoDB Loader (Optional)
# -----------------------------------------------------------------------------
resource "aws_iam_role" "s3_to_dynamodb_loader_lambda_role" {
  count = var.enable_s3_loader ? 1 : 0

  name = "${var.project_name}-S3ToDynamoDBLoaderLambdaRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-S3ToDynamoDBLoaderLambdaRole"
    Environment = var.environment
  }
}

resource "aws_iam_policy" "s3_to_dynamodb_loader_lambda_policy" {
  count = var.enable_s3_loader ? 1 : 0

  name        = "${var.project_name}-S3ToDynamoDBLoaderLambdaPolicy"
  description = "IAM policy for Lambda to read S3 and write to DynamoDB"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = [
          "s3:GetObject"
        ],
        Effect   = "Allow",
        Resource = "${aws_s3_bucket.inventory_uploads.arn}/*" # Allow reading from the S3 bucket
      },
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.inventory.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "s3_to_dynamodb_loader_lambda_attach" {
  count = var.enable_s3_loader ? 1 : 0

  role       = aws_iam_role.s3_to_dynamodb_loader_lambda_role[0].name
  policy_arn = aws_iam_policy.s3_to_dynamodb_loader_lambda_policy[0].arn
}

data "archive_file" "s3_to_dynamodb_loader_lambda_zip" {
  count = var.enable_s3_loader ? 1 : 0

  type        = "zip"
  source_dir  = "${path.module}/lambda/s3_to_dynamodb_loader"
  output_path = "${path.module}/lambda/s3_to_dynamodb_loader.zip"
}

resource "aws_lambda_function" "s3_to_dynamodb_loader" {
  count = var.enable_s3_loader ? 1 : 0

  function_name    = "${var.project_name}-S3ToDynamoDBLoader"
  handler          = "main.lambda_handler"
  runtime          = "python3.12"
  role             = aws_iam_role.s3_to_dynamodb_loader_lambda_role[0].arn
  filename         = data.archive_file.s3_to_dynamodb_loader_lambda_zip[0].output_path
  source_code_hash = data.archive_file.s3_to_dynamodb_loader_lambda_zip[0].output_base64sha256
  timeout          = 60 # Might need more time for large files
  memory_size      = 256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME = aws_dynamodb_table.inventory.name
    }
  }

  tags = {
    Name        = "${var.project_name}-S3ToDynamoDBLoader"
    Environment = var.environment
  }
}
#
#

