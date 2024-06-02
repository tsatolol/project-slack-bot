terraform {
  required_version = ">= 1.5.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.16"
    }

    null = {
      source  = "hashicorp/null"
      version = ">= 3.1.1"
    }
  }
}

provider "aws" {
  region = var.region
}



