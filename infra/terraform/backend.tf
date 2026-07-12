# ---------------------------------------------------------------------------
# REMOTE STATE — READ THIS BEFORE YOU RUN ANYTHING
# ---------------------------------------------------------------------------
# This repository is PUBLIC.
#
# Since the move to OIDC federation, this stack no longer mints a long-lived
# AWS credential, so state no longer contains a plaintext secret key. That
# removes the catastrophic case. It does NOT make state publishable:
#
#   - It records the AWS account id, role and queue ARNs, and queue URLs. That
#     is a free reconnaissance map of the account for anyone who wants one, and
#     the repo is public.
#   - It is the shared source of truth for what exists. Two people applying
#     against two divergent local copies is how you get orphaned queues that
#     nothing manages and nobody notices.
#
# So state still goes to S3 from the very first `terraform init`: private,
# versioned, locked. Versioning is the undo button for a corrupted or truncated
# write — without it, a bad write loses the mapping between config and real
# resources and recovery means importing everything by hand.
#
# `.gitignore` refuses `*.tfstate*` as a second line of defence. That is a
# backstop, not the plan. Do not weaken it.
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
