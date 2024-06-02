variable "account_id" {}
variable "region" {}
variable "bucket_name" {}
variable "slack_bot_token" {}
variable "slack_signing_secret" {}

variable "ecr_lambda_producer_name" {
  type    = string
  default = "slack-bot-ecr-lambda-producer"
}

variable "ecr_lambda_consumer_name" {
  type    = string
  default = "slack-bot-ecr-lambda-consumer"
}

