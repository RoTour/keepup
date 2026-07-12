# ---------------------------------------------------------------------------
# REMOTE STATE — READ THIS BEFORE YOU RUN ANYTHING
# ---------------------------------------------------------------------------
# This repository is PUBLIC.
#
# Terraform state is not a build artifact, it is a transcript. It records the
# IAM user ARN, the access key id, the queue URLs, and — because AWS only ever
# reveals it once, at creation — the IAM SECRET ACCESS KEY IN PLAINTEXT.
#
# A local `terraform.tfstate` that reaches a commit publishes live credentials
# to the internet. `git rm` does not fix that: the blob stays in history, and
# the key must be assumed compromised and rotated.
#
# So state goes to S3 from the very first `terraform init`. There is never a
# moment where a state file exists on a developer's disk inside the repo.
# `.gitignore` already refuses `*.tfstate*` as a second line of defence — treat
# that as a backstop, not as the plan. Do not weaken it.
#
# The bucket below must EXIST BEFORE the first `terraform init`. Terraform
# cannot create the bucket that holds its own state — that is the bootstrap
# chicken-and-egg. See infra/terraform/README.md § Bootstrap for the exact
# one-time commands (create bucket, enable versioning, block public access).
# ---------------------------------------------------------------------------

terraform {
  backend "s3" {
    # >>> PLACEHOLDER — replace with the bucket you created during bootstrap.
    # Bucket names are globally unique across all of AWS, so this value cannot
    # be a sensible default; it must be yours.
    bucket = "REPLACE_ME-keepup-tfstate"

    key    = "sqs/terraform.tfstate"
    region = "eu-west-3"

    # S3-native state locking (Terraform >= 1.10). Writes a companion .tflock
    # object in the same bucket, so two concurrent applies cannot interleave.
    # This replaces the old DynamoDB lock table — no extra resource to bootstrap.
    use_lockfile = true

    encrypt = true
  }
}
