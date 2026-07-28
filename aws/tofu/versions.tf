# SPDX-License-Identifier: GPL-3.0-or-later

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Application = "familycontrol"
      ManagedBy   = "OpenTofu"
      Environment = "learning"
    }
  }
}
