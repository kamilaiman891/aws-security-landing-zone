
# ==========================================
# MODULE 1: The Foundation (IAM Roles)
# ==========================================

# Generic Trust Policy to allow "AssumeRole"
data "aws_iam_policy_document" "trust_policy" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::000000000000:root"]
    }
  }
}

resource "aws_iam_role" "security_admin" {
  name               = "SecurityAdminRole"
  assume_role_policy = data.aws_iam_policy_document.trust_policy.json
}

resource "aws_iam_role" "log_audit" {
  name               = "LogAuditRole"
  assume_role_policy = data.aws_iam_policy_document.trust_policy.json
}

resource "aws_iam_role" "application_engineer" {
  name               = "ApplicationEngineerRole"
  assume_role_policy = data.aws_iam_policy_document.trust_policy.json
}

# ==========================================
# MODULE 2: The Vault (Centralized Logging)
# ==========================================

resource "aws_s3_bucket" "audit_vault" {
  bucket = "central-audit-logging-vault-tf"
}

# The bucket policy preventing the Application Engineer from deleting logs
resource "aws_s3_bucket_policy" "vault_lockdown" {
  bucket = aws_s3_bucket.audit_vault.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudTrailWrite"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.audit_vault.arn}/*"
      },
      {
        Sid       = "DenyAppEngineerDelete"
        Effect    = "Deny"
        Principal = { AWS = aws_iam_role.application_engineer.arn }
        Action    = ["s3:DeleteObject", "s3:DeleteBucket"]
        Resource  = [
          aws_s3_bucket.audit_vault.arn,
          "${aws_s3_bucket.audit_vault.arn}/*"
        ]
      }
    ]
  })
}

# ==========================================
# MODULE 3: The Workload (VPC & Networking)
# ==========================================

resource "aws_vpc" "app_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "TF-AppVPC" }
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.app_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true

  tags = { Name = "TF-PublicSubnet" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.app_vpc.id
  tags   = { Name = "TF-AppIGW" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.app_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# The Security Group allowing Web and SSH traffic
resource "aws_security_group" "app_sg" {
  name        = "TF-AppSecurityGroup"
  description = "Allow HTTP and SSH inbound traffic"
  vpc_id      = aws_vpc.app_vpc.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Simulated EC2 Instance
resource "aws_instance" "app_server" {
  ami           = "ami-0c55b159cbfafe1f0" # Dummy AMI ID for LocalStack
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.app_sg.id]

  tags = { Name = "TF-AppServer" }
}

# ==========================================
# MODULE 4: The Watchtower (Security Alarm)
# ==========================================

resource "aws_sqs_queue" "security_alerts_queue" {
  name = "tf-security-alerts-queue"
}

resource "aws_cloudwatch_event_rule" "unauthorized_api_call" {
  name        = "TF-UnauthorizedAPICallRule"
  description = "Triggered when an AccessDenied event occurs."

  event_pattern = jsonencode({
    detail = {
      errorCode = ["AccessDenied", "UnauthorizedOperation"]
    }
  })
}

resource "aws_cloudwatch_event_target" "sqs_target" {
  rule      = aws_cloudwatch_event_rule.unauthorized_api_call.name
  target_id = "SendToSQS"
  arn       = aws_sqs_queue.security_alerts_queue.arn
}
