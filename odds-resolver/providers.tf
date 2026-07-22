terraform {
  required_version = ">= 1.15"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "hakusoft-terraform-state"
    key          = "odds-resolver/terraform.tfstate"
    region       = "ap-northeast-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "odds-resolver"
      ManagedBy = "terraform"
    }
  }
}

locals {
  name = "odds-resolver"
}

data "aws_caller_identity" "current" {}
