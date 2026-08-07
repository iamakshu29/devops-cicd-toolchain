terraform {
  required_version = ">= 1.9.0, < 2.0.0" # terraform version

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.46" # provder version
    }
  }
}

provider "aws" {
  region = "us-east-1"
}