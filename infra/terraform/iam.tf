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

  # The SOURCE queues only — the two the worker legitimately enqueues onto. The
  # DLQs are deliberately excluded from send: nothing ever sends to a DLQ by
  # hand, SQS's redrive machinery is the only writer. Granting send on a DLQ
  # would let a compromised CI token forge "grading abandoned" messages into
  # the very queue that exists to preserve honest evidence of give-ups.
  grading_source_queue_arns = [
    aws_sqs_queue.grading.arn,
    aws_sqs_queue.grading_test.arn,
  ]

  # Either the provider we just created, or the one the account already had.
  # See var.create_github_oidc_provider for why this is switchable.
  github_oidc_provider_arn = (
    var.create_github_oidc_provider
    ? aws_iam_openid_connect_provider.github[0].arn
    : var.existing_github_oidc_provider_arn
  )

  # The OIDC subject this role will accept, e.g.
  # "repo:RoTour/keepup:environment:ci".
  #
  # It is scoped to a named GitHub ENVIRONMENT ("ci"), not to the whole repo.
  # "repo:<owner>/<repo>:*" would trust every ref, tag and pull_request run in
  # the repo; this trusts only a job that declares `environment: ci`. The gap
  # that closes is a future `pull_request_target` or a compromised action on
  # some branch inheriting the role — none of which run in the `ci` environment
  # unless a maintainer wired them to. GitHub only stamps the
  # "...:environment:ci" subject on a job that names that environment, so a job
  # that forgets it fails AssumeRole closed (the safe direction), which is the
  # contract recorded in WORKFLOW §8.
  #
  # It still does NOT cross repositories: the "repo:<owner>/<repo>:" prefix is
  # fixed and var.github_repository is validated to reject wildcards, so this
  # cannot widen to "repo:*:*".
  #
  # var.github_oidc_subject_suffix carries the "environment:ci" part, so the
  # environment name lives in one variable rather than being spliced here.
  github_oidc_subject = "repo:${var.github_repository}:${var.github_oidc_subject_suffix}"
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

# Two statements, split by which queues each action belongs on. Same five
# data-plane actions as before, still no wildcards — but SendMessage is now
# held only on the source queues, never on the DLQs.
resource "aws_iam_role_policy" "grading_worker" {
  name = "${var.queue_name_prefix}-sqs"
  role = aws_iam_role.grading_worker.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Enqueue a grading job. Source queues ONLY. A grading job is never
        # placed on a DLQ by a client — SQS's redrive does that automatically
        # after maxReceiveCount — so send rights on a DLQ have no legitimate
        # use and one illegitimate one: forging give-up evidence. Withheld.
        Sid      = "EnqueueOntoSourceQueuesOnly"
        Effect   = "Allow"
        Action   = "sqs:SendMessage"
        Resource = local.grading_source_queue_arns
      },
      {
        # Consume, acknowledge, inspect and extend leases. Legitimate on all
        # four queues: the contract suite receives and deletes from the DLQ to
        # prove a job reached it, and reads its depth.
        Sid    = "ConsumeAndInspectAllQueues"
        Effect = "Allow"
        Action = [
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
