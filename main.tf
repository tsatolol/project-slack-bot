# ----------------------------------------------------------
# S3 bucket
# ----------------------------------------------------------
resource "aws_s3_bucket" "slack_bot_bucket" {
  bucket        = var.bucket_name
  force_destroy = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "encryption" {
  bucket = aws_s3_bucket.slack_bot_bucket.bucket

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "access_block" {
  bucket = aws_s3_bucket.slack_bot_bucket.bucket

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ----------------------------------------------------------
# IAM role
# ----------------------------------------------------------
# iam_lambda_1
resource "aws_iam_role" "iam_lambda_producer" {
  name = "iam-lambda-producer"

  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Action = "sts:AssumeRole"
          Effect = "Allow"
          Sid    = ""
          Principal = {
            Service = "lambda.amazonaws.com"
          }
        }
      ]
    }
  )
}

resource "aws_iam_policy" "iam_policy_lambda_producer" {
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "sqs:SendMessage"
        ],
        "Resource" : [
          "arn:aws:sqs:${var.region}:${var.account_id}:${aws_sqs_queue.bedrock_backend_queue.name}"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "iam_policy_lambda_producer_1" {
  role       = aws_iam_role.iam_lambda_producer.name
  policy_arn = aws_iam_policy.iam_policy_lambda_producer.arn
}

resource "aws_iam_role_policy_attachment" "iam_policy_lambda_producer_2" {
  role       = aws_iam_role.iam_lambda_producer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# iam_lambda_2
resource "aws_iam_role" "iam_lambda_consumer" {
  name = "iam-lambda-consumer"

  assume_role_policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Action    = "sts:AssumeRole"
          Effect    = "Allow"
          Sid       = ""
          Principal = { Service = "lambda.amazonaws.com" }
        }
      ]
    }
  )
}

resource "aws_iam_policy" "iam_policy_lambda_consumer" {
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "sqs:GetQueueAttributes",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
        ],
        "Resource" : [
          "arn:aws:sqs:${var.region}:${var.account_id}:${aws_sqs_queue.bedrock_backend_queue.name}"
        ]
        }, {
        "Effect" : "Allow",
        "Action" : [
          "s3:GetObject",
          "s3:PutObject"
        ],
        "Resource" : "arn:aws:s3:::${aws_s3_bucket.slack_bot_bucket.bucket}/*"
        }, {
        "Effect" : "Allow",
        "Action" : ["bedrock:InvokeModel"],
        "Resource" : "arn:aws:bedrock:${var.region}::foundation-model/stability.stable-diffusion-xl-v1"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "iam_policy_lambda_consumer_1" {
  role       = aws_iam_role.iam_lambda_consumer.name
  policy_arn = aws_iam_policy.iam_policy_lambda_consumer.arn
}

resource "aws_iam_role_policy_attachment" "iam_policy_lambda_consumer_2" {
  role       = aws_iam_role.iam_lambda_consumer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ----------------------------------------------------------
# ECR
# ----------------------------------------------------------
# ecr_lambda_producer
resource "aws_ecr_repository" "ecr_lambda_producer" {
  name         = var.ecr_lambda_producer_name
  force_delete = true
}

# ecr_lambda_consumer
resource "aws_ecr_repository" "ecr_lambda_consumer" {
  name         = var.ecr_lambda_consumer_name
  force_delete = true
}

# ----------------------------------------------------------
# Docker build and push
# ----------------------------------------------------------
# container_lambda_producer
resource "null_resource" "producer_build_and_push" {
  triggers = {
    file_content_sha1 = sha1(join("", [for f in ["container/Dockerfile.producer"] : filesha1(f)]))
  }

  provisioner "local-exec" {
    command = <<-EOT

# docker login
aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${var.account_id}.dkr.ecr.${var.region}.amazonaws.com
# docker build
docker build -t ${var.ecr_lambda_producer_name} -f ./container/Dockerfile.producer ./container
# image tagging
docker tag ${var.ecr_lambda_producer_name}:latest ${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_lambda_producer_name}:latest
# push
docker push ${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_lambda_producer_name}:latest

    EOT
  }
}

# container_lambda_consumer
resource "null_resource" "consumer_build_and_push" {
  triggers = {
    file_content_sha1 = sha1(join("", [for f in ["container/Dockerfile.consumer"] : filesha1(f)]))
  }

  provisioner "local-exec" {
    command = <<-EOT

# docker login
aws ecr get-login-password --region ${var.region} | docker login --username AWS --password-stdin ${var.account_id}.dkr.ecr.${var.region}.amazonaws.com
# docker build
docker build -t ${var.ecr_lambda_consumer_name} -f ./container/Dockerfile.consumer ./container
# image tagging
docker tag ${var.ecr_lambda_consumer_name}:latest ${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_lambda_consumer_name}:latest
# push
docker push ${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${var.ecr_lambda_consumer_name}:latest

    EOT
  }
}

# ----------------------------------------------------------
# Lambda
# ----------------------------------------------------------
# Lambda_producer
resource "aws_lambda_function" "lambda_producer" {
  function_name = "lambda-producer"
  image_uri     = "${aws_ecr_repository.ecr_lambda_producer.repository_url}:latest"
  package_type  = "Image"
  role          = aws_iam_role.iam_lambda_producer.arn

  environment {
    variables = {
      SLACK_BOT_TOKEN      = var.slack_bot_token
      SLACK_SIGNING_SECRET = var.slack_signing_secret
      SQS_QUEUE_NAME       = aws_sqs_queue.bedrock_backend_queue.url
    }
  }

  depends_on = [
    null_resource.producer_build_and_push
  ]
}

# Lambda_consumer
resource "aws_lambda_function" "lambda_consumer" {
  function_name = "lambda-consumer"
  image_uri     = "${aws_ecr_repository.ecr_lambda_consumer.repository_url}:latest"
  package_type  = "Image"
  role          = aws_iam_role.iam_lambda_consumer.arn
  memory_size   = 256
  timeout       = 30

  environment {
    variables = {
      SLACK_BOT_TOKEN = var.slack_bot_token
      S3_BUCKET_NAME  = aws_s3_bucket.slack_bot_bucket.bucket
    }
  }

  depends_on = [
    null_resource.consumer_build_and_push
  ]
}

# ----------------------------------------------------------
# SQS
# ----------------------------------------------------------
resource "aws_sqs_queue" "bedrock_backend_queue" {
  name = "bedrock_backend_queue"
}

resource "aws_lambda_event_source_mapping" "sqs_mapping" {
  event_source_arn = aws_sqs_queue.bedrock_backend_queue.arn
  function_name    = aws_lambda_function.lambda_consumer.arn
}

# ----------------------------------------------------------
# API Gateway
# ----------------------------------------------------------
resource "aws_apigatewayv2_api" "apigw_slack_bot" {
  name          = "slack-bot-app"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_stage" "apigw_stage_slack_bot" {
  api_id = aws_apigatewayv2_api.apigw_slack_bot.id

  name        = "v1"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.cloudwatch_apigw.arn

    format = jsonencode({
      requestId               = "$context.requestId"
      sourceIp                = "$context.identity.sourceIp"
      requestTime             = "$context.requestTime"
      protocol                = "$context.protocol"
      httpMethod              = "$context.httpMethod"
      resourcePath            = "$context.resourcePath"
      routeKey                = "$context.routeKey"
      status                  = "$context.status"
      responseLength          = "$context.responseLength"
      integrationErrorMessage = "$context.integrationErrorMessage"
      }
    )
  }
}

resource "aws_apigatewayv2_integration" "apigw_integration_slack_bot" {
  api_id = aws_apigatewayv2_api.apigw_slack_bot.id

  integration_uri    = aws_lambda_function.lambda_producer.invoke_arn
  integration_type   = "AWS_PROXY"
  integration_method = "POST"
}

resource "aws_apigatewayv2_route" "apigw_route_slack_bot" {
  api_id = aws_apigatewayv2_api.apigw_slack_bot.id

  route_key = "ANY /slack/events"
  target    = "integrations/${aws_apigatewayv2_integration.apigw_integration_slack_bot.id}"
}

resource "aws_lambda_permission" "apigw_permission" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_producer.function_name
  principal     = "apigateway.amazonaws.com"

  source_arn = "${aws_apigatewayv2_api.apigw_slack_bot.execution_arn}/*/*"
}

# ----------------------------------------------------------
# CloudWatch
# ----------------------------------------------------------
# log_group_aipgw
resource "aws_cloudwatch_log_group" "cloudwatch_apigw" {
  name              = "/aws/api_gw/${aws_apigatewayv2_api.apigw_slack_bot.name}"
  retention_in_days = 30
}

# log_group_lambda_producer
resource "aws_cloudwatch_log_group" "cloudwatch_lambda_producer" {
  name              = "/aws/lambda/${aws_lambda_function.lambda_producer.function_name}"
  retention_in_days = 30
}

# log_group_lambda_consumer
resource "aws_cloudwatch_log_group" "cloudwatch_lambda_consumer" {
  name              = "/aws/lambda/${aws_lambda_function.lambda_consumer.function_name}"
  retention_in_days = 30
}
