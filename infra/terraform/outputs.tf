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
# The CI identity.
#
# NOTHING HERE IS SENSITIVE, AND NOTHING HERE NEEDS TO BE.
#
# A role ARN is an identifier, not a credential. Knowing it gets you nothing:
# to assume the role you must present an OIDC token that GitHub only mints for
# a workflow running in this repository. So the role ARN can be pasted into a
# public workflow file, logged, and screenshotted with no consequence — which
# is exactly why the static access key it replaced is gone.
#
# There is no `sensitive = true` in this stack any more, because there is no
# secret in this stack any more.
# ---------------------------------------------------------------------------

output "ci_role_arn" {
  description = "ARN of the role GitHub Actions assumes via OIDC. -> `role-to-assume` in aws-actions/configure-aws-credentials. Not a secret."
  value       = aws_iam_role.grading_worker.arn
}

output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider trusted by the CI role — the one this stack created, or the pre-existing one it was pointed at."
  value       = local.github_oidc_provider_arn
}

output "github_oidc_subject" {
  description = "The OIDC subject condition the CI role's trust policy accepts. Anything not matching this cannot assume the role."
  value       = local.github_oidc_subject
}
