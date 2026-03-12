terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  
  # These settings tell Terraform to talk to LocalStack instead of real AWS
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  
  endpoints {
    s3       = "http://s3.localhost.localstack.cloud:4566"
    sts      = "http://localhost:4566"
    iam      = "http://localhost:4566"
    sqs      = "http://localhost:4566"
    events   = "http://localhost:4566"
    ec2      = "http://localhost:4566"
  }
}
