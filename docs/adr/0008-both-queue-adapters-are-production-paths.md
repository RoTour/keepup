# Both queue adapters are production paths, and one contract suite is the evidence

`KEEPUP_QUEUE=rabbitmq` runs the broker as a container beside the app on the VPS. `KEEPUP_QUEUE=sqs` makes the same VPS long-poll a real SQS queue in `eu-west-3`. Both are supported in production and the choice is one environment variable. Terraform provisions the queue, its dead-letter queue, the redrive policy, and an IAM user scoped to a single queue ARN.

Long-polling `eu-west-3` from a European VPS adds roughly fifteen milliseconds to an operation that takes eight seconds. The latency argument against this does not survive contact with the numbers.

## The evidence for "interchangeable" is a test suite, not a second class

Writing two classes that implement one interface proves nothing; nobody doubted it was possible. The claim becomes real only through **one port contract suite executed twice** — once against RabbitMQ in Testcontainers, once against a real SQS queue — asserting the same redelivery, visibility, and give-up behaviour from both. That suite is the deliverable. The second adapter is just what it runs against.

This matters because [ADR-0003](./0003-the-evaluation-queue-is-at-least-once-and-unordered.md)'s entire argument rests on real broker semantics: visibility timeouts, `ApproximateReceiveCount`, redrive policies. Those are the things a fake gets subtly wrong.

## Considered Options

- **Production is RabbitMQ; SQS runs only in CI against a real AWS queue.** Rejected, though it is honest and cheap. The swap would never have happened in production, and the first question anyone asks is whether it has.
- **Production is RabbitMQ; SQS is LocalStack forever.** Rejected. LocalStack approximates exactly the semantics the design depends on, so the decoupling claim would reduce to "a fake accepted both implementations." The Terraform would provision infrastructure nothing ever runs against.

## Consequences

Production can be flipped from RabbitMQ to SQS by changing one variable and restarting, while a class is running. This is the demonstration the project exists to produce.

Long-lived AWS credentials live on a VPS. The IAM policy is scoped to one queue ARN and the key is rotated. This is accepted for a prototype and would not be accepted for anything else.

The SQS queue exists permanently and costs a negligible amount. Terraform is therefore not decoration — without it there is nothing for the SQS adapter to talk to.
