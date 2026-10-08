terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.4"
    }
  }
}

variable "s3_bucket_to_monitor" {
  description = "Name of the S3 bucket to check and remediate"
  type        = string
  default     = "REPLACE_WITH_BUCKET_NAME"
}

data "archive_file" "s3_public_access_lambda" {
  type        = "zip"
  output_path = "${path.module}/s3-public-access-lambda.zip"

  source {
    filename = "lambda_function.py"
    content  = <<-PYTHON
			import json
			import boto3

			s3 = boto3.client("s3")
			PUBLIC_GROUP_URIS = {
				"http://acs.amazonaws.com/groups/global/AllUsers",
				"http://acs.amazonaws.com/groups/global/AuthenticatedUsers",
			}

			def has_open_principal(statement):
				if statement.get("Condition"):
					return False

				principal = statement.get("Principal")
				if principal == "*":
					return True
				if isinstance(principal, dict):
					aws_principal = principal.get("AWS")
					return aws_principal == "*" or (
						isinstance(aws_principal, list) and "*" in aws_principal
					)
				return False

			def lambda_handler(event, context):
				bucket = event.get("bucket")
				if not bucket:
					raise ValueError("The event must contain a bucket name")

				policy_statements_removed = 0
				try:
					policy_response = s3.get_bucket_policy(Bucket=bucket)
				except s3.exceptions.ClientError as error:
					if error.response["Error"]["Code"] != "NoSuchBucketPolicy":
						raise
				else:
					policy = json.loads(policy_response["Policy"])
					original_statements = policy.get("Statement", [])
					statements = original_statements if isinstance(original_statements, list) else [original_statements]
					retained_statements = []
					for statement in statements:
						if has_open_principal(statement):
							policy_statements_removed += 1
						else:
							retained_statements.append(statement)

					if policy_statements_removed:
						if retained_statements:
							policy["Statement"] = retained_statements
							s3.put_bucket_policy(Bucket=bucket, Policy=json.dumps(policy))
						else:
							s3.delete_bucket_policy(Bucket=bucket)

				acl = s3.get_bucket_acl(Bucket=bucket)
				retained_grants = [
					grant for grant in acl.get("Grants", [])
					if not (
						grant.get("Grantee", {}).get("Type") == "Group"
						and grant.get("Grantee", {}).get("URI") in PUBLIC_GROUP_URIS
					)
				]
				acl_grants_removed = len(acl.get("Grants", [])) - len(retained_grants)
				if acl_grants_removed:
					s3.put_bucket_acl(
						Bucket=bucket,
						AccessControlPolicy={"Owner": acl["Owner"], "Grants": retained_grants},
					)

			policy_still_public = False
			try:
				policy_still_public = s3.get_bucket_policy_status(Bucket=bucket)["PolicyStatus"]["IsPublic"]
			except s3.exceptions.ClientError as error:
				if error.response["Error"]["Code"] != "NoSuchBucketPolicy":
					raise

			result = {
				"bucket": bucket,
				"policy_statements_removed": policy_statements_removed,
				"acl_grants_removed": acl_grants_removed,
				"policy_still_public": policy_still_public,
			}
			print(json.dumps(result))
			return result
		PYTHON
  }
}

resource "aws_iam_role" "s3_public_access_lambda" {
  name = "s3-public-access-remediation-lambda"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "s3_public_access_lambda" {
  name = "s3-public-access-remediation"
  role = aws_iam_role.s3_public_access_lambda.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketPolicy",
          "s3:PutBucketPolicy",
          "s3:DeleteBucketPolicy",
          "s3:GetBucketPolicyStatus",
          "s3:GetBucketAcl",
          "s3:PutBucketAcl",
        ]
        Resource = "arn:aws:s3:::${var.s3_bucket_to_monitor}"
      }
    ]
  })
}

resource "aws_lambda_function" "s3_public_access" {
  function_name    = "s3-public-access-remediation"
  role             = aws_iam_role.s3_public_access_lambda.arn
  runtime          = "python3.12"
  handler          = "lambda_function.lambda_handler"
  filename         = data.archive_file.s3_public_access_lambda.output_path
  source_code_hash = data.archive_file.s3_public_access_lambda.output_base64sha256
  timeout          = 30
}

resource "aws_cloudwatch_event_rule" "s3_public_access_schedule" {
  name                = "s3-public-access-remediation-schedule"
  description         = "Checks the configured S3 bucket for public access every five minutes."
  schedule_expression = "rate(5 minutes)"
	is_enabled          = var.s3_bucket_to_monitor != "REPLACE_WITH_BUCKET_NAME"
}

resource "aws_cloudwatch_event_target" "s3_public_access_schedule" {
  rule      = aws_cloudwatch_event_rule.s3_public_access_schedule.name
  target_id = "s3-public-access-remediation-lambda"
  arn       = aws_lambda_function.s3_public_access.arn
  input     = jsonencode({ bucket = var.s3_bucket_to_monitor })
}

resource "aws_lambda_permission" "allow_eventbridge_s3_public_access" {
  statement_id  = "AllowEventBridgeInvokeS3PublicAccessRemediation"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_public_access.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.s3_public_access_schedule.arn
}
