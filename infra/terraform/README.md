# `keepup` — SQS grading queues (Terraform)

Provisions the **SQS** side of the grading work queue in **eu-west-3**.

Grading is asynchronous: a learner submits, a grading job goes on a queue, a
worker picks it up, asks an LLM to grade it, and writes the result back. There
are two interchangeable queue implementations behind one port — **RabbitMQ**
(the deployed one) and **SQS** (built and contract-tested in CI, not deployed).
This directory is the SQS half, and it exists mainly so the contract suite has
a real broker to run against.

---

## Read this first: the repo is public

Terraform state is a transcript, not a build artifact. It records the IAM user
ARN, the queue URLs, the access key id, and — because AWS reveals it exactly
once, at creation — **the IAM secret access key in plaintext**.

A `terraform.tfstate` that reaches a commit in this repository publishes live
AWS credentials to the internet. Deleting the file later does not help: the
blob stays in git history and the key has to be assumed compromised and
rotated.

So: **state goes to S3 from the very first `terraform init`.** Never to the
repo, not even "temporarily", not even "just to try a plan". `.gitignore`
already refuses `*.tfstate*`, `.terraform/`, and `*.tfvars` — that is a
backstop, not the plan. Do not weaken it.

---

## What gets created

Four queues, one IAM user, one access key. Nothing else.

| Queue | Visibility | maxReceiveCount | Long poll | Retention | What it's for |
|---|---|---|---|---|---|
| `keepup-grading` | **120s** | 3 | 20s | 4d (default) | Production grading jobs. |
| `keepup-grading-dlq` | default | — | — | 14d | Jobs we gave up on. Kept for a human to read. |
| `keepup-grading-test` | **2s** | 2 | 0s | 5m | CI contract suite. |
| `keepup-grading-test-dlq` | default | — | — | 5m | CI contract suite's DLQ. |

### Why 120s on the production queue

It is a correctness constraint, not a round number.

When a worker receives a grading job, SQS hides it for the visibility timeout
and waits to be told the work is done. If that timeout expires first, SQS
assumes the worker died and hands **the same message to another worker — while
the first is still running**. A grading job makes an LLM call whose worst case
is ~8s, and that tail moves when the model, the prompt, or the provider's load
moves. A visibility timeout anywhere near the work duration does not produce a
retry; it produces **two workers grading one submission concurrently**, racing
to write two different grades onto one learner's answer. Silently, and
non-deterministically.

120s is ~15x the observed worst case, so the number survives the LLM getting
slower without anyone re-deriving it. Too high costs a genuinely-crashed
worker's job a late retry. Too low costs a corrupted grade. Those are not
comparable — that asymmetry is the whole argument.

`variables.tf` enforces a 60s floor so the value cannot be casually tuned down.
If a job legitimately needs longer, the worker should extend its own lease with
`ChangeMessageVisibility` (the permission is granted) rather than the timeout
being lowered.

### Why a second, short-visibility queue pair exists

The contract suite has to prove one specific thing: when a grading job exhausts
its delivery attempts, the system produces **exactly one** "grading abandoned"
outcome — not zero (silently swallowed), not two (duplicated). That assertion
only means anything if the test actually drives a message through every
delivery attempt and out into the DLQ.

Against the production settings that costs
`maxReceiveCount x visibilityTimeout = 3 x 120s = 6 minutes` of wall clock,
spent asleep, per assertion. Nobody keeps that in CI. It gets marked slow, then
skipped, then deleted — and the give-up path ships untested, which is exactly
the path that only ever runs when something is already wrong.

Against `keepup-grading-test` the same journey costs `2 x 2s ≈ 4 seconds`. Same
code, same port, same broker semantics, same assertion — a queue with its clock
turned down. Two extra queues is a cheaper price than losing coverage of the
poison-message path.

**These values are the point of that queue.** They are not the production
values that someone forgot to update, and copying them onto `keepup-grading`
would corrupt grades.

### The IAM credential

One user, `keepup-grading-worker`, with a single inline policy:

- **Actions:** `SendMessage`, `ReceiveMessage`, `DeleteMessage`,
  `GetQueueAttributes`, `ChangeMessageVisibility`. Nothing else. No `sqs:*`.
  Notably absent: `CreateQueue`, `DeleteQueue`, `PurgeQueue`,
  `SetQueueAttributes`, `ListQueues`. Terraform manages the queues; the worker
  only uses them.
- **Resources:** the four queue ARNs, enumerated. **No wildcard.**

If this key leaks, the complete blast radius is: someone can push and pull
grading jobs on four named queues in one region. They cannot enumerate the
account's other queues, create or delete anything, or reach any other service.
That turns a leak into a bounded incident fixed by rotating one key.

---

## Bootstrap (one time, by hand)

Terraform cannot create the bucket that holds its own state — that is the
chicken-and-egg. Do this **once**, before the first `terraform init`.

You need AWS credentials with admin-ish rights for these steps (your own IAM
user / SSO profile — *not* the worker key this stack produces).

### 1. Create the state bucket

Bucket names are globally unique across all of AWS, so pick your own and
substitute it everywhere below.

```sh
export TF_STATE_BUCKET="keepup-tfstate-<something-unique>"
export AWS_REGION=eu-west-3

aws s3api create-bucket \
  --bucket "$TF_STATE_BUCKET" \
  --region eu-west-3 \
  --create-bucket-configuration LocationConstraint=eu-west-3
```

### 2. Enable versioning

Non-optional. Versioning is the undo button for a corrupted or truncated state
file — without it, a bad write loses the mapping between the config and the
real resources, and recovery means importing everything by hand.

```sh
aws s3api put-bucket-versioning \
  --bucket "$TF_STATE_BUCKET" \
  --versioning-configuration Status=Enabled
```

### 3. Block public access

This is the bucket that will hold a plaintext IAM secret key. Belt and braces.

```sh
aws s3api put-public-access-block \
  --bucket "$TF_STATE_BUCKET" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### 4. Enable default encryption at rest

```sh
aws s3api put-bucket-encryption \
  --bucket "$TF_STATE_BUCKET" \
  --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```

### 5. Point `backend.tf` at the bucket

`backend.tf` ships with a **placeholder**:

```hcl
bucket = "REPLACE_ME-keepup-tfstate"
```

Replace it with `$TF_STATE_BUCKET` and commit that (a bucket name is not a
secret; its contents are). No DynamoDB lock table is needed — the backend uses
S3-native locking (`use_lockfile = true`, Terraform >= 1.10).

If you would rather not hard-code the bucket, delete the `bucket`/`key`/`region`
lines and pass them at init time instead:

```sh
terraform init \
  -backend-config="bucket=$TF_STATE_BUCKET" \
  -backend-config="key=sqs/terraform.tfstate" \
  -backend-config="region=eu-west-3"
```

---

## Apply

```sh
cd infra/terraform

terraform init      # first run migrates nothing; state starts in S3
terraform plan      # read it
terraform apply
```

To validate the config **without** AWS credentials and without touching the
backend (this is what CI and a reviewer do):

```sh
terraform init -backend=false
terraform validate
terraform fmt -check
```

---

## Getting the outputs into GitHub Actions

Six secrets. Read them straight out of `terraform output` and pipe them into
`gh` — do not stage them in a file. An untracked file today is a committed file
after the next `git add -A`.

```sh
cd infra/terraform

gh secret set AWS_ACCESS_KEY_ID     --body "$(terraform output -raw grading_worker_access_key_id)"
gh secret set AWS_SECRET_ACCESS_KEY --body "$(terraform output -raw grading_worker_secret_access_key)"
gh secret set AWS_REGION            --body "$(terraform output -raw aws_region)"

gh secret set SQS_GRADING_QUEUE_URL      --body "$(terraform output -raw grading_queue_url)"
gh secret set SQS_GRADING_TEST_QUEUE_URL --body "$(terraform output -raw grading_test_queue_url)"
gh secret set SQS_GRADING_TEST_DLQ_URL   --body "$(terraform output -raw grading_test_dlq_url)"
```

The contract suite runs against `SQS_GRADING_TEST_QUEUE_URL` and asserts the
give-up path by reading `SQS_GRADING_TEST_DLQ_URL`. It must **never** be pointed
at the production queue.

The two credential outputs are marked `sensitive = true`, so a bare
`terraform output` redacts them and they will not leak into a CI log. `-raw`
is the deliberate act of reading one.

### Rotating the key

```sh
terraform taint aws_iam_access_key.grading_worker
terraform apply
# then re-run the two gh secret set commands above
```

---

## Files

| File | |
|---|---|
| `backend.tf` | S3 remote state. **Contains a placeholder bucket name you must replace.** |
| `versions.tf` | Pinned Terraform + AWS provider, default tags. |
| `variables.tf` | Tunables, with guardrails on the ones that can corrupt grades. |
| `queues.tf` | The four queues and their redrive policies. |
| `iam.tf` | The worker user, its ARN-scoped policy, and its access key. |
| `outputs.tf` | Queue URLs, queue ARNs, credentials (sensitive). |
| `terraform.tfvars.example` | Copy to `terraform.tfvars` (git-ignored) to override defaults. |
