# ---------------------------------------------------------------------------
# Queue URLs — what the application and the contract suite are configured with.
# We hand out URLs rather than names on purpose: resolving a queue by name at
# runtime would require sqs:GetQueueUrl, and that permission is not granted.
# ---------------------------------------------------------------------------

output "grading_queue_url" {
  description = "URL of the production grading queue."
  value       = aws_sqs_queue.grading.id
}

output "grading_dlq_url" {
  description = "URL of the production grading dead-letter queue."
  value       = aws_sqs_queue.grading_dlq.id
}

output "grading_test_queue_url" {
  description = "URL of the CI contract-test grading queue (2s visibility, maxReceiveCount 2)."
  value       = aws_sqs_queue.grading_test.id
}

output "grading_test_dlq_url" {
  description = "URL of the CI contract-test dead-letter queue."
  value       = aws_sqs_queue.grading_test_dlq.id
}

# ---------------------------------------------------------------------------
# Queue ARNs — the exact set the IAM policy is scoped to.
# ---------------------------------------------------------------------------

output "grading_queue_arn" {
  description = "ARN of the production grading queue."
  value       = aws_sqs_queue.grading.arn
}

output "grading_dlq_arn" {
  description = "ARN of the production grading dead-letter queue."
  value       = aws_sqs_queue.grading_dlq.arn
}

output "grading_test_queue_arn" {
  description = "ARN of the CI contract-test grading queue."
  value       = aws_sqs_queue.grading_test.arn
}

output "grading_test_dlq_arn" {
  description = "ARN of the CI contract-test dead-letter queue."
  value       = aws_sqs_queue.grading_test_dlq.arn
}

output "aws_region" {
  description = "Region the queues live in. The SQS client needs it."
  value       = var.aws_region
}

# ---------------------------------------------------------------------------
# Credentials.
#
# Both are marked sensitive so Terraform will not print them in plan/apply logs
# or in CI output. Read them deliberately:
#
#   terraform output -raw grading_worker_access_key_id
#   terraform output -raw grading_worker_secret_access_key
#
# Paste straight into GitHub Actions secrets. Do not redirect them to a file —
# an untracked file today is a committed file after someone runs `git add -A`.
# ---------------------------------------------------------------------------

output "grading_worker_access_key_id" {
  description = "Access key id for the SQS worker IAM user. -> GitHub secret AWS_ACCESS_KEY_ID."
  value       = aws_iam_access_key.grading_worker.id
  sensitive   = true
}

output "grading_worker_secret_access_key" {
  description = "Secret access key for the SQS worker IAM user. -> GitHub secret AWS_SECRET_ACCESS_KEY."
  value       = aws_iam_access_key.grading_worker.secret
  sensitive   = true
}

output "grading_worker_user_arn" {
  description = "ARN of the SQS worker IAM user."
  value       = aws_iam_user.grading_worker.arn
}
