terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Pinned to a single major line. Bumping a major version of the AWS
      # provider can silently change resource defaults; do it deliberately,
      # never as a drive-by.
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.common_tags
  }
}

locals {
  common_tags = {
    Project   = "keepup"
    Component = "grading-queue"
    ManagedBy = "terraform"
  }
}
