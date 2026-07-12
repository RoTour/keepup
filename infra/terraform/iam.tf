# ===========================================================================
# THE CI IDENTITY — GITHUB OIDC FEDERATION, NO LONG-LIVED CREDENTIAL
#
# GitHub Actions assumes a role here by presenting a short-lived OIDC token
# that GitHub itself mints for the workflow run. AWS verifies that token
# against GitHub's OIDC provider and hands back temporary STS credentials that
# expire in about an hour.
#
# THERE IS NO ACCESS KEY IN THIS STACK. Not in GitHub secrets, not in Terraform
# state, not on anyone's laptop. That is the entire point of this design and it
# is deliberate: the repository is PUBLIC, so a static key would be a permanent
# secret guarding a public front door, and it would sit in plaintext in state
# forever because AWS only reveals it once. Nothing here needs rotating,
# because nothing here is long-lived. Do not "simplify" this back into an
# aws_iam_access_key.
#
# Three things carry the security of this design, and none is negotiable:
#
#   1. THE TRUST POLICY IS SCOPED TO ONE REPOSITORY. The `sub` claim must match
#      "repo:<owner>/<repo>:*". Leaving the subject as a bare wildcard would let
#      a workflow in ANY repository on github.com — including one a stranger
#      creates this afternoon — assume this role. The subject condition is the
#      only thing standing between "our CI" and "all of GitHub".
#
#   2. RESOURCES ARE ENUMERATED, NEVER WILDCARDED. Not "arn:aws:sqs:*", not
#      "*". Exactly the four queue ARNs. The worst a compromised workflow can
#      do is push and pull grading jobs on four named queues in one region: it
#      cannot enumerate the account's other queues, create or delete anything,
#      or reach another service.
#
#   3. ACTIONS ARE THE MINIMUM THE WORKER ACTUALLY PERFORMS. No sqs:*.
#      Notably absent: CreateQueue, DeleteQueue, PurgeQueue, SetQueueAttributes,
#      ListQueues. Terraform manages the queues; the worker only uses them. A
#      role that cannot reshape the infrastructure it runs on cannot be used to
#      reshape the infrastructure it runs on.
# ===========================================================================

locals {
  # The complete, closed set of queues this role may touch. If a fifth queue is
  # ever added and CI needs it, it gets added HERE, explicitly and visibly in a
  # diff — which is the entire point of not using a wildcard.
  grading_queue_arns = [
    aws_sqs_queue.grading.arn,
    aws_sqs_queue.grading_dlq.arn,
    aws_sqs_queue.grading_test.arn,
    aws_sqs_queue.grading_test_dlq.arn,
  ]

  # Either the provider we just created, or the one the account already had.
  # See var.create_github_oidc_provider for why this is switchable.
  github_oidc_provider_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : var.existing_github_oidc_provider_arn
  )

  # The OIDC subject this role will accept, e.g. "repo:RoTour/keepup:*".
  #
  # The trailing "*" covers every ref, environment and event in THIS repository
  # (branches, tags, pull_request runs). It does NOT cover other repositories:
  # the "repo:<owner>/<repo>:" prefix is fixed, and var.github_repository is
  # validated to reject wildcards so this cannot silently widen to "repo:*:*".
  #
  # To tighten further later — e.g. only master, or only a named GitHub
  # Environment — narrow this to "repo:<owner>/<repo>:ref:refs/heads/master" or
  # "repo:<owner>/<repo>:environment:ci". That is a policy change, not a code
  # change; it happens right here.
  github_oidc_subject = "repo:${var.github_repository}:*"
}

# ---------------------------------------------------------------------------
# The GitHub OIDC provider.
#
# An AWS account may hold exactly ONE OIDC provider per URL. If
# token.actions.githubusercontent.com is already registered — which it will be
# if any other stack in this account already uses GitHub Actions — then
# creating it again is an EntityAlreadyExists error at apply time, and the
# apply dies halfway. Hence the switch: set create_github_oidc_provider = false
# and pass the existing ARN instead. README § Bootstrap has the one command
# that tells you which case you are in. CHECK IT BEFORE THE FIRST APPLY.
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  # The audience. aws-actions/configure-aws-credentials requests exactly this.
  client_id_list = ["sts.amazonaws.com"]

  # Deliberately omitted: thumbprint_list.
  #
  # For OIDC endpoints hosted by well-known root CAs — GitHub's is one — IAM
  # verifies the TLS chain against its own trusted-CA library and ignores any
  # thumbprint you supply. Pinning GitHub's intermediate certificate here would
  # be security theatre that also breaks the apply the day GitHub rotates it.
  # Leave it out.
}

# ---------------------------------------------------------------------------
# The role GitHub Actions assumes.
# ---------------------------------------------------------------------------
resource "aws_iam_role" "grading_worker" {
  name        = "${var.queue_name_prefix}-ci"
  path        = "/keepup/"
  description = "Assumed by GitHub Actions via OIDC to run the SQS grading contract suite."

  # One hour. The contract suite runs in seconds; there is no reason for the
  # credential to outlive the job by much.
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubActionsOIDC"
        Effect = "Allow"
        Principal = {
          Federated = local.github_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          # The audience must be STS. Without this, a GitHub token minted for
          # some other audience entirely could be replayed at AWS.
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          # THE LOAD-BEARING LINE. Scopes the trust to this one repository.
          # StringLike (not StringEquals) because of the trailing "*" — but the
          # "repo:<owner>/<repo>:" prefix is fixed and cannot be widened.
          StringLike = {
            "token.actions.githubusercontent.com:sub" = local.github_oidc_subject
          }
        }
      },
    ]
  })

  lifecycle {
    precondition {
      condition = (
        var.create_github_oidc_provider
        || (var.existing_github_oidc_provider_arn != null && var.existing_github_oidc_provider_arn != "")
      )
      error_message = "create_github_oidc_provider is false, so existing_github_oidc_provider_arn must be set to the ARN of the GitHub OIDC provider already registered in this account."
    }
  }

  tags = {
    Name    = "${var.queue_name_prefix}-ci"
    Purpose = "SQS grading queue producer/consumer (CI contract suite, via OIDC)"
  }
}

# Unchanged from the static-key version: same five data-plane actions, same
# four enumerated queue ARNs. Only the identity that carries them changed.
resource "aws_iam_role_policy" "grading_worker" {
  name = "${var.queue_name_prefix}-sqs"
  role = aws_iam_role.grading_worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GradingQueueDataPlaneOnly"
        Effect = "Allow"
        Action = [
          # Enqueue a grading job.
          "sqs:SendMessage",
          # Claim a grading job.
          "sqs:ReceiveMessage",
          # Acknowledge a finished grading job so it is not redelivered.
          "sqs:DeleteMessage",
          # Read depth / redrive config. The contract suite asserts on
          # ApproximateNumberOfMessages to prove a job reached the DLQ.
          "sqs:GetQueueAttributes",
          # Extend the lease on an in-flight job. This is the sanctioned way to
          # handle an LLM call that runs long — the worker asks for more time
          # rather than anyone lowering the visibility timeout in queues.tf.
          "sqs:ChangeMessageVisibility",
        ]
        # Enumerated. Four ARNs. No wildcard, no "arn:aws:sqs:eu-west-3:*:*".
        Resource = local.grading_queue_arns
      },
    ]
  })
}
