# ===========================================================================
# THE CI CREDENTIAL
#
# This is the identity GitHub Actions uses to run the SQS contract suite. The
# repository is PUBLIC, so this credential will be read by strangers and it
# will be probed. Two rules follow from that, and neither is negotiable:
#
#   1. RESOURCES ARE ENUMERATED, NEVER WILDCARDED. Not "arn:aws:sqs:*", not
#      "*". Exactly the four queue ARNs below. If this key leaks, the entire
#      blast radius is: someone can push and pull grading jobs on four named
#      queues in one region. They cannot enumerate the account's other queues,
#      cannot create queues, cannot delete them, cannot touch any other
#      service. A leak is then an incident about junk grading jobs — annoying,
#      bounded, and fixed by rotating one key.
#
#   2. ACTIONS ARE THE MINIMUM THE WORKER ACTUALLY PERFORMS. No sqs:*.
#      Notably absent: CreateQueue, DeleteQueue, PurgeQueue, SetQueueAttributes,
#      ListQueues. Terraform manages the queues; the worker only uses them.
#      A credential that cannot reshape the infrastructure it runs on cannot be
#      used to reshape the infrastructure it runs on.
# ===========================================================================

locals {
  # The complete, closed set of queues this credential may touch. If a fifth
  # queue is ever added and the credential needs it, it gets added HERE,
  # explicitly and visibly in a diff — which is the entire point of not using
  # a wildcard.
  grading_queue_arns = [
    aws_sqs_queue.grading.arn,
    aws_sqs_queue.grading_dlq.arn,
    aws_sqs_queue.grading_test.arn,
    aws_sqs_queue.grading_test_dlq.arn,
  ]
}

resource "aws_iam_user" "grading_worker" {
  name = "${var.queue_name_prefix}-worker"
  path = "/keepup/"

  tags = {
    Name    = "${var.queue_name_prefix}-worker"
    Purpose = "SQS grading queue producer/consumer (app + CI contract suite)"
  }
}

resource "aws_iam_user_policy" "grading_worker" {
  name = "${var.queue_name_prefix}-worker-sqs"
  user = aws_iam_user.grading_worker.name

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

# The long-lived access key that goes into GitHub Actions secrets.
#
# NOTE: the secret lands in Terraform state in plaintext — AWS only ever
# reveals it once, at creation, so there is nowhere else for Terraform to keep
# it. This is the concrete reason backend.tf insists on a private, versioned,
# public-access-blocked S3 bucket and why a local .tfstate must never be
# committed. Read the secret out via `terraform output`, paste it into GitHub
# Actions secrets, and do not write it to a file.
resource "aws_iam_access_key" "grading_worker" {
  user = aws_iam_user.grading_worker.name
}
