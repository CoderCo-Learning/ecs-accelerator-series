terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # null = {
    #   source  = "hashicorp/null"
    #   version = "~> 3.0"
    # }
  }
}

provider "aws" {
  region = "us-east-1"
}