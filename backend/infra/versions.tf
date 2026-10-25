terraform {
  required_version = "~> 1.17.0"

  required_providers {
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.8"
    }

    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.70"
    }
  }
}
