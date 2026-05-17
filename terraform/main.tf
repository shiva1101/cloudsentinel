terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  # Remote state (uncomment for team usage)
  # backend "s3" {
  #   bucket         = "cloudsentinel-terraform-state"
  #   key            = "infra/terraform.tfstate"
  #   region         = var.aws_region
  #   encrypt        = true
  #   dynamodb_table = "cloudsentinel-state-lock"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "CloudSentinel"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "Shivam Singh"
    }
  }
}
