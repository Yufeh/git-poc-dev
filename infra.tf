terraform {
	required_providers {
		aws = {
			source  = "hashicorp/aws"
			version = ">= 4.0"
		}
	}
	required_version = ">= 1.0"
}

provider "aws" {
	region = var.aws_region
}

variable "aws_region" {
	description = "AWS region to create resources in"
	type        = string
	default     = "us-east-1"
}

variable "bucket_name" {
	description = "Name of the S3 bucket to create (must be globally unique)"
	type        = string
}

resource "aws_s3_bucket" "this" {
	bucket = var.bucket_name

	versioning {
		enabled = true
	}

	server_side_encryption_configuration {
		rule {
			apply_server_side_encryption_by_default {
				sse_algorithm = "AES256"
			}
		}
	}

	tags = {
		Name        = var.bucket_name
		Environment = "dev"
	}
}

output "bucket_id" {
	value = aws_s3_bucket.this.id
}

output "bucket_arn" {
	value = aws_s3_bucket.this.arn
}

/*
To create the bucket:
1. Set variable bucket_name via -var or terraform.tfvars
2. Run: terraform init && terraform apply
*/