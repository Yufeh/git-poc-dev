terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

# ---- Variables you should change ----
variable "instance_type" {
  type    = string
  default = "t3.micro"
}

# Use an AMI that matches your region (e.g. Amazon Linux 2023)
variable "ami_id" {
  type = string
  # example placeholder:
  # default = "ami-0123456789abcdef0"
}

variable "key_name" {
  type = string
  # This must be an existing EC2 key pair name in AWS
  # default = "my-keypair"
}

# ---- Security Group (allow SSH) ----
resource "aws_security_group" "ssh_sg" {
  name        = "ssh-sg"
  description = "Allow SSH"
  vpc_id      = "replace-me-with-your-default-or-vpc-id"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_PUBLIC_IP/32"] # e.g. "203.0.113.10/32"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---- EC2 Instance ----
resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = var.key_name

  vpc_security_group_ids = [aws_security_group.ssh_sg.id]

  tags = {
    Name = "tf-ec2"
  }
}