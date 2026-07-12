variable "aws_region" {
  description = "AWS region hosting the grading queues."
  type        = string
  default     = "eu-west-3"
}

variable "queue_name_prefix" {
  description = "Base name for the grading queues. Queue names are derived from it."
  type        = string
  default     = "keepup-grading"
}

# ---------------------------------------------------------------------------
# Production queue tuning
# ---------------------------------------------------------------------------

variable "visibility_timeout_seconds" {
  description = <<-EOT
    How long a grading job stays invisible to other consumers after it is
    received. MUST exceed the worst-case duration of the work, LLM call
    included. See queues.tf for why 120s and why lowering it corrupts grades.
  EOT
  type        = number
  default     = 120

  validation {
    # An LLM grading call has been observed at ~8s worst case. Anything in the
    # same order of magnitude as the work itself is a double-grading bug
    # waiting to happen, so refuse to even plan it.
    condition     = var.visibility_timeout_seconds >= 60
    error_message = "Visibility timeout must be >= 60s: it has to comfortably exceed the ~8s worst-case LLM grading call, or the same submission gets graded twice concurrently."
  }
}

variable "max_receive_count" {
  description = "Delivery attempts before a grading job is moved to the dead-letter queue."
  type        = number
  default     = 3

  validation {
    condition     = var.max_receive_count >= 1 && var.max_receive_count <= 10
    error_message = "max_receive_count must be between 1 and 10: retry a few times, then give up loudly."
  }
}

variable "receive_wait_time_seconds" {
  description = "Long-poll duration. 20s is the AWS maximum and minimises both empty receives and cost."
  type        = number
  default     = 20

  validation {
    condition     = var.receive_wait_time_seconds >= 0 && var.receive_wait_time_seconds <= 20
    error_message = "receive_wait_time_seconds must be between 0 and 20 (AWS long-poll maximum)."
  }
}

variable "dlq_message_retention_seconds" {
  description = "How long a dead-lettered grading job is kept for inspection. 14 days is the AWS maximum."
  type        = number
  default     = 1209600 # 14 days
}

# ---------------------------------------------------------------------------
# GitHub OIDC federation — the CI identity. See iam.tf.
# ---------------------------------------------------------------------------

variable "github_repository" {
  description = <<-EOT
    The "owner/repo" whose GitHub Actions workflows may assume the CI role.
    Fixes the "repo:<owner>/<repo>:" prefix of the OIDC subject condition.
    Widen it and you hand the role to strangers.
  EOT
  type        = string
  default     = "RoTour/keepup"

  validation {
    # A "*" here would produce a subject like "repo:*:...", which any repository
    # on github.com would match. That is the one catastrophic misconfiguration
    # available in this file, so refuse it at plan time rather than trusting a
    # code review to catch it.
    condition     = can(regex("^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$", var.github_repository))
    error_message = "github_repository must be exactly \"owner/repo\" with no wildcards: it is what scopes the OIDC trust policy to this repository rather than to all of GitHub."
  }
}

variable "github_oidc_subject_suffix" {
  description = <<-EOT
    The part of the OIDC subject AFTER "repo:<owner>/<repo>:". Narrows the trust
    WITHIN the repository. Default "environment:ci" trusts only a job that
    declares `environment: ci` — not every ref/tag/PR run. The full subject
    becomes "repo:<owner>/<repo>:environment:ci".

    A job that omits `environment: ci` gets a subject that does not match and
    fails AssumeRole closed — the safe direction. The matching CI contract is
    recorded in WORKFLOW §8.

    Other valid narrowings: "ref:refs/heads/master", "environment:production".
  EOT
  type        = string
  default     = "environment:ci"

  validation {
    # The subject may legitimately contain ":" and "/" (e.g. "environment:ci",
    # "ref:refs/heads/master"), so those are allowed. A "*" is NOT — it would
    # re-open the "trust every ref/PR in the repo" hole this suffix exists to
    # close, or worse. If it does not match this class, refuse it at plan time.
    condition     = can(regex("^[A-Za-z0-9._/:-]+$", var.github_oidc_subject_suffix))
    error_message = "github_oidc_subject_suffix must be a concrete subject segment such as \"environment:ci\" or \"ref:refs/heads/master\" — no wildcards. A \"*\" would re-widen the trust it exists to narrow."
  }
}

variable "create_github_oidc_provider" {
  description = <<-EOT
    Whether to create the token.actions.githubusercontent.com OIDC provider.

    An AWS account may hold exactly ONE OIDC provider per URL, so if the
    account already has one (because some other stack already uses GitHub
    Actions), creating it again fails the apply with EntityAlreadyExists. In
    that case set this to false and pass existing_github_oidc_provider_arn.

    README § Bootstrap has the one-line check that tells you which case you are
    in. Run it before the first apply.
  EOT
  type        = bool
  default     = true
}

variable "existing_github_oidc_provider_arn" {
  description = <<-EOT
    ARN of the GitHub OIDC provider already registered in this account. Only
    used — and required — when create_github_oidc_provider is false.
  EOT
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# CI contract-test queue tuning — deliberately hostile settings, see queues.tf
# ---------------------------------------------------------------------------

variable "test_visibility_timeout_seconds" {
  description = "Visibility timeout for the CI contract-test queue. Short on purpose so the give-up path runs in seconds."
  type        = number
  default     = 2
}

variable "test_max_receive_count" {
  description = "Delivery attempts before the CI contract-test queue dead-letters. Small on purpose."
  type        = number
  default     = 2
}

variable "test_message_retention_seconds" {
  description = <<-EOT
    Retention on the CI test queues. Short on purpose: it makes the queues
    self-cleaning between CI runs, so a message stranded by a crashed or
    cancelled run cannot leak into the next run and break an assertion that
    counts outcomes. Minimum accepted by AWS is 60s.
  EOT
  type        = number
  default     = 300 # 5 minutes

  validation {
    condition     = var.test_message_retention_seconds >= 60 && var.test_message_retention_seconds <= 3600
    error_message = "Keep CI test retention between 60s and 1h: long enough to survive a slow runner, short enough to self-clean between runs."
  }
}
