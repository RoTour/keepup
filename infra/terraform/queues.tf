# ===========================================================================
# PRODUCTION GRADING QUEUE PAIR
#
# A grading job is: "take this learner's submission, ask an LLM to grade it,
# write the result back". It is the deployed path's work unit. The SQS
# implementation here sits behind the same port as the RabbitMQ one.
# ===========================================================================

# Dead-letter queue. Declared first: the main queue's redrive policy points at
# it, so it must exist before the queue that feeds it.
#
# A message that lands here is a grading job we gave up on. It is kept for the
# full 14 days rather than dropped, because "why did this submission never get
# a grade?" is a question that gets asked days later, by a human, and the
# message body is the only evidence.
resource "aws_sqs_queue" "grading_dlq" {
  name = "${var.queue_name_prefix}-dlq"

  message_retention_seconds = var.dlq_message_retention_seconds

  tags = {
    Name = "${var.queue_name_prefix}-dlq"
    Role = "dead-letter"
  }
}

resource "aws_sqs_queue" "grading" {
  name = var.queue_name_prefix

  # -------------------------------------------------------------------------
  # VISIBILITY TIMEOUT — 120 SECONDS. DO NOT "TIDY" THIS DOWN.
  #
  # This is not a round number someone liked. It is a correctness constraint.
  #
  # When a worker receives a grading job, SQS hides the message for this long
  # and waits to be told the work is done. If the timeout expires first, SQS
  # assumes the worker died and hands the SAME message to ANOTHER worker —
  # while the first one is still running.
  #
  # A grading job makes an LLM call. Worst case observed: ~8s, and that is a
  # tail that moves when the model, the prompt, or the provider's load moves.
  # If the visibility timeout is anywhere near the work duration, the outcome
  # is not a retry — it is TWO WORKERS GRADING ONE SUBMISSION CONCURRENTLY,
  # racing to write two different grades for the same answer. That failure is
  # silent, non-deterministic, and lands on a learner's record.
  #
  # 120s is a deliberately wide margin over an ~8s worst case: roughly 15x, so
  # the number survives the LLM getting slower without anyone re-deriving it.
  # The cost of it being too high is a genuinely-crashed worker's job being
  # retried up to 2 minutes late. The cost of it being too low is corrupted
  # grades. Those are not comparable, and that asymmetry is the whole argument.
  #
  # If you think this should be lower, the change you actually want is for the
  # worker to extend the timeout itself (ChangeMessageVisibility) — which is
  # why that permission is granted in iam.tf.
  # -------------------------------------------------------------------------
  visibility_timeout_seconds = var.visibility_timeout_seconds

  # Long polling: hold the receive open for up to 20s waiting for work rather
  # than returning empty immediately. Fewer empty receives, lower bill, lower
  # latency than a poll loop with a sleep in it.
  receive_wait_time_seconds = var.receive_wait_time_seconds

  # Retry a few times, then stop. A grading job that has failed 3 times is not
  # going to succeed on the 4th — it is a poison message, and the useful thing
  # to do is get it out of the way and preserve it for a human.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.grading_dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = {
    Name = var.queue_name_prefix
    Role = "grading-jobs"
  }
}

# Lock the DLQ down to its one legitimate source queue. Without this, any queue
# in the account could dead-letter into it and pollute the evidence.
resource "aws_sqs_queue_redrive_allow_policy" "grading_dlq" {
  queue_url = aws_sqs_queue.grading_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.grading.arn]
  })
}

# ===========================================================================
# CI CONTRACT-TEST QUEUE PAIR — SHORT VISIBILITY, ON PURPOSE
#
# WHY THIS PAIR EXISTS AT ALL:
#
# The contract suite has to prove one specific thing about the give-up path:
# when a grading job exhausts its delivery attempts, the system produces
# EXACTLY ONE "grading abandoned" outcome — not zero (silently swallowed), not
# two (duplicated). That assertion is only meaningful if the test actually
# drives a message through every delivery attempt and out the other side into
# the DLQ.
#
# Against the production settings, doing that honestly costs
# maxReceiveCount x visibilityTimeout = 3 x 120s = 6 MINUTES of wall clock, per
# assertion, spent asleep. Nobody puts that in CI. What happens instead is the
# test gets marked slow, then skipped, then deleted — and the give-up path
# ships untested, which is precisely the path that only ever runs when
# something is already wrong.
#
# Against these settings the same journey costs 2 x 2s = ~4 SECONDS. Same code,
# same port, same broker semantics, same assertion — just a queue whose clock
# is turned down. The test suite is the customer for this queue pair, and it is
# cheaper to provision two extra queues than to lose coverage of the one path
# that catches poison messages.
#
# These values are the point of this queue. They are not a mistake, they are
# not "the prod values that someone forgot to update", and copying them onto
# the production queue above would corrupt grades. See the visibility timeout
# comment there.
# ===========================================================================

resource "aws_sqs_queue" "grading_test_dlq" {
  name = "${var.queue_name_prefix}-test-dlq"

  # Short retention: self-cleaning between CI runs. A message stranded by a
  # cancelled or crashed run must not survive into the next run, where it would
  # be counted by an assertion that expects EXACTLY ONE abandoned outcome.
  message_retention_seconds = var.test_message_retention_seconds

  tags = {
    Name = "${var.queue_name_prefix}-test-dlq"
    Role = "dead-letter"
    Env  = "ci"
  }
}

resource "aws_sqs_queue" "grading_test" {
  name = "${var.queue_name_prefix}-test"

  # 2s, NOT 120s. Deliberate. See the block comment above.
  # A test that waits 6 minutes is a test that gets deleted.
  visibility_timeout_seconds = var.test_visibility_timeout_seconds

  # No long polling here: CI wants an empty receive to come back immediately so
  # "the queue is drained" resolves fast instead of parking for 20s.
  receive_wait_time_seconds = 0

  message_retention_seconds = var.test_message_retention_seconds

  # 2 attempts, NOT 3. The suite only needs "attempts get exhausted", and each
  # attempt it doesn't take is 2s of CI it doesn't spend.
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.grading_test_dlq.arn
    maxReceiveCount     = var.test_max_receive_count
  })

  tags = {
    Name = "${var.queue_name_prefix}-test"
    Role = "grading-jobs-contract-test"
    Env  = "ci"
  }
}

resource "aws_sqs_queue_redrive_allow_policy" "grading_test_dlq" {
  queue_url = aws_sqs_queue.grading_test_dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.grading_test.arn]
  })
}
