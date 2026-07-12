# `keepup` — SQS grading queues (Terraform)

Provisions the **SQS** side of the grading work queue in **eu-west-3**.

Grading is asynchronous: a learner submits, a grading job goes on a queue, a
worker picks it up, asks an LLM to grade it, and writes the result back. There
are two interchangeable queue implementations behind one port — **RabbitMQ**
(the deployed one) and **SQS** (built and contract-tested in CI, not deployed).
This directory is the SQS half, and it exists mainly so the contract suite has
a real broker to run against.

---

## There is no long-lived AWS credential in this project

This is the single most important fact about this stack, and it is deliberate.

CI authenticates to AWS by **GitHub OIDC federation**. A workflow run presents
a short-lived token that GitHub mints for it; AWS verifies that token and hands
back temporary credentials that expire in about an hour.

So:

- **No access key in GitHub secrets.** What CI needs is a *role ARN*, and a
  role ARN is an identifier, not a credential — knowing it gets you nothing.
- **No secret in Terraform state.** Nothing in this stack is marked
  `sensitive`, because nothing in it is a secret.
- **Nothing to rotate.** There is no key with an age, no key to leak, no key to
  find in a git history five years from now.

The repository is **public**. A static access key here would have been a
permanent secret guarding a public front door — and, because AWS reveals a
secret key exactly once at creation, it would have sat in plaintext in
Terraform state forever. OIDC removes the secret rather than protecting it.

**Do not "simplify" this back into an IAM user with an access key.** If you
find yourself reaching for `aws_iam_access_key`, you are undoing the point.

State still goes to S3 and still must never be committed — see
[below](#read-this-too-state-still-goes-to-s3).

---

## What gets created

Four queues, one OIDC provider, one assumable role. No users, no keys.

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

### The CI identity

One role, `keepup-grading-ci`, assumable **only** by a GitHub Actions job that
runs in **this repository** *and* declares the **`ci` environment**.

**Trust policy** — two conditions, both load-bearing:

| Claim | Condition | Value |
|---|---|---|
| `aud` | `StringEquals` | `sts.amazonaws.com` |
| `sub` | `StringLike` | `repo:RoTour/keepup:environment:ci` |

The `sub` condition is what separates "our CI" from "every repository on
github.com" — the `repo:RoTour/keepup:` prefix is fixed, and `variables.tf`
validates `github_repository` against `^owner/repo$`, rejecting wildcards at
plan time so it cannot widen to `repo:*:*`.

The `:environment:ci` suffix narrows further, *within* the repo. It is not
`:*`. GitHub only stamps the `environment:ci` subject onto a job that names
`environment: ci`, so the role trusts exactly that job — not arbitrary refs,
tags, or `pull_request` runs that happen to inherit the workflow. A job that
forgets the environment gets a non-matching subject and **fails AssumeRole
closed** (the safe direction). The suffix lives in `github_oidc_subject_suffix`,
which is guarded by its own regex — it accepts concrete segments like
`environment:ci` or `ref:refs/heads/master` and rejects `*`.

> **Contract (WORKFLOW §8):** the CI slice's `sqs-contract` job MUST declare
> both `environment: ci` and `permissions: id-token: write`. Miss either and
> the assume fails closed.

**Permission policy** — least-privilege, split into two statements:

- **`sqs:SendMessage`** — on the two **source** queues only (`keepup-grading`,
  `keepup-grading-test`). The DLQs are deliberately excluded: nothing sends to a
  DLQ by hand (redrive is automatic), so a send grant there has no use except to
  let a compromised token forge "grading abandoned" messages into the evidence
  the DLQ exists to preserve.
- **`sqs:ReceiveMessage`, `sqs:DeleteMessage`, `sqs:GetQueueAttributes`,
  `sqs:ChangeMessageVisibility`** — on all four queues. The suite receives from
  and reads the DLQ to prove a job reached it.
- No `sqs:*`. Notably absent: `CreateQueue`, `DeleteQueue`, `PurgeQueue`,
  `SetQueueAttributes`, `ListQueues`. Terraform manages the queues; the worker
  only uses them.
- **Resources:** the queue ARNs, enumerated. **No wildcard.**

Worst case, if the `ci` job were compromised: the attacker can push to two named
queues and pull from four, in one region, for the ~1h life of one token. They
cannot forge give-up evidence into a DLQ, enumerate the account's other queues,
create or delete anything, or reach any other service.

### Encryption at rest

All four queues set `sqs_managed_sse_enabled = true`. Message bodies are learner
submissions — educational PII — so encryption at rest (SSE-SQS, the SQS-owned
key) is set explicitly on every queue rather than left to an account default
that could be flipped elsewhere. It is free, needs no KMS key, and is
transparent to clients.

---

## Read this too: state still goes to S3

OIDC removed the plaintext secret from state. It did not make state
publishable. State still records the AWS account id, the role and queue ARNs,
and the queue URLs — a free reconnaissance map of the account, in a public
repo. It is also the shared source of truth for what exists; two people applying
from two divergent local copies is how you get orphaned queues that nothing
manages and nobody notices.

So state lives in S3 from the very first `terraform init`: private, versioned,
locked. `.gitignore` refuses `*.tfstate*` as a backstop — that is a second line
of defence, not the plan. Do not weaken it.

---

## Bootstrap (one time, by hand)

Use your own AWS credentials for these steps — your SSO / admin profile. (The
role this stack creates is for CI, and cannot create anything anyway.)

### 0. Check whether the GitHub OIDC provider already exists — DO THIS FIRST

An AWS account may hold **exactly one** OIDC provider per URL. If
`token.actions.githubusercontent.com` is already registered — which it will be
if *anything else* in this account already uses GitHub Actions — then creating
it again fails with `EntityAlreadyExists`, **halfway through the apply**, after
the queues have already been made.

```sh
aws iam list-open-id-connect-providers \
  --query "OpenIDConnectProviderList[?contains(Arn, 'token.actions.githubusercontent.com')].Arn" \
  --output text
```

- **Empty output** → the provider does not exist. Leave the defaults alone;
  Terraform will create it.
- **Prints an ARN** → the provider already exists. Put this in
  `terraform.tfvars`:

  ```hcl
  create_github_oidc_provider       = false
  existing_github_oidc_provider_arn = "<the ARN printed above>"
  ```

  A `lifecycle` precondition on the role stops the plan with a clear message if
  you set the flag to `false` and forget the ARN.

### 1. Create the state bucket

Bucket names are globally unique across all of AWS, so pick your own and
substitute it everywhere below.

```sh
export TF_STATE_BUCKET="keepup-tfstate-<something-unique>"

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

terraform init
terraform plan      # read it
terraform apply
```

To validate the config **without** AWS credentials and without touching the
backend (this is what a reviewer does):

```sh
terraform init -backend=false
terraform validate
terraform fmt -check -recursive
```

---

## Wiring CI to the role

There are **no secrets to set**. CI needs two values, and neither is
confidential:

```sh
cd infra/terraform
terraform output -raw ci_role_arn   # arn:aws:iam::<account-id>:role/keepup/keepup-grading-ci
terraform output -raw aws_region    # eu-west-3
```

Paste them straight into the workflow, or keep them as repo *variables*
(`gh variable set`, **not** `gh secret set` — they are not secrets) if you'd
rather not commit the account id:

```sh
gh variable set AWS_ROLE_ARN --body "$(terraform output -raw ci_role_arn)"
gh variable set AWS_REGION   --body "$(terraform output -raw aws_region)"
```

The workflow needs three things, and two of them are the ones people forget:

- **`environment: ci` on the job.** The trust policy's subject is
  `repo:RoTour/keepup:environment:ci`; GitHub only stamps that subject onto a
  job that names this environment. Omit it and the assume fails closed.
- **`permissions: id-token: write`.** Lets the runner request an OIDC token at
  all. Its absence fails with a misleading *"Not authorized to perform
  sts:AssumeRoleWithWebIdentity"* — which reads like a trust-policy problem but
  means the runner never got a token to present.
- The role ARN and region (below). Not secret.

```yaml
permissions:
  id-token: write   # REQUIRED: lets the runner request an OIDC token.
  contents: read    # checkout

jobs:
  sqs-contract:
    runs-on: ubuntu-latest
    environment: ci   # REQUIRED: the trust policy is scoped to this environment.
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ vars.AWS_ROLE_ARN }}
          aws-region: ${{ vars.AWS_REGION }}
      # No aws-access-key-id. No aws-secret-access-key. That is the point.

      - run: ./gradlew test --tests '*Sqs*'
        env:
          SQS_GRADING_TEST_QUEUE_URL: ${{ vars.SQS_GRADING_TEST_QUEUE_URL }}
          SQS_GRADING_TEST_DLQ_URL: ${{ vars.SQS_GRADING_TEST_DLQ_URL }}
```

The contract suite runs against `grading_test_queue_url` and asserts the
give-up path by reading `grading_test_dlq_url`. It must **never** be pointed at
the production queue.

> The CI slice owns the actual workflow file. The snippet above is the contract
> it should implement, not the workflow itself.

### Running the contract suite locally

OIDC only works **from inside a GitHub Actions runner** — GitHub is the only
thing that can mint the token, so there is no role for you to assume from your
laptop and nothing worth copying out of CI.

Locally, authenticate as **yourself**, with an identity that already has rights
to the queues:

```sh
aws sso login --profile keepup      # or however you normally authenticate
export AWS_PROFILE=keepup
export AWS_REGION=eu-west-3

export SQS_GRADING_TEST_QUEUE_URL="$(terraform -chdir=infra/terraform output -raw grading_test_queue_url)"
export SQS_GRADING_TEST_DLQ_URL="$(terraform -chdir=infra/terraform output -raw grading_test_dlq_url)"

./gradlew test --tests '*Sqs*'
```

Do **not** mint a shared access key "just for local dev" and pass it around —
that reintroduces exactly the long-lived credential this design removed. Each
developer authenticates as themselves.

Note the test queues are **shared**: two people running the suite at the same
time will steal each other's messages. Coordinate, or point at a private copy.

---

## Files

| File | |
|---|---|
| `backend.tf` | S3 remote state. **Contains a placeholder bucket name you must replace.** |
| `versions.tf` | Pinned Terraform + AWS provider, default tags. |
| `variables.tf` | Tunables, with guardrails on the two that can cause real damage. |
| `queues.tf` | The four queues and their redrive policies. |
| `iam.tf` | The GitHub OIDC provider, the CI role, and its ARN-scoped policy. |
| `outputs.tf` | Queue URLs, queue ARNs, role ARN. Nothing sensitive. |
| `terraform.tfvars.example` | Copy to `terraform.tfvars` (git-ignored) to override defaults. |
