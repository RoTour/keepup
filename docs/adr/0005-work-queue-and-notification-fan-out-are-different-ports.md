# The work queue and the notification fan-out are different ports

Grading a Submission is **competing-consumers** work: exactly one worker must pick up each message. Telling the Trainer's browser that a grading landed is **fan-out**: every web node must hear it, because no node knows which of them holds that Trainer's WebSocket.

These are different delivery semantics, and only one of them is portable. SQS and RabbitMQ both do competing consumers. Only RabbitMQ does fan-out natively — an SQS message is delivered to exactly one consumer, so reaching N nodes would mean SNS plus one dynamically provisioned SQS queue per node.

So they are two ports. `IEvaluationWorkQueue` has an SQS adapter and a RabbitMQ adapter, and they are genuinely interchangeable. `ISessionNotifier` is implemented on Postgres `LISTEN`/`NOTIFY`, which we already run, and never touches the broker at all.

## Considered Options

- **Do fan-out on the broker.** Rejected. It is where the interchangeability claim would actually have broken: the RabbitMQ adapter is a fanout exchange with an exclusive auto-delete queue per node, while the SQS adapter needs SNS and runtime queue provisioning. The two topologies are not the same shape, and the port would be a lie.
- **One process: web and worker together, single replica.** Rejected. It removes the problem by removing the async story — a worker OOM would take the classroom down, and the design could never demonstrate the thing it exists to demonstrate. It also breaks silently the first time the platform scales to two replicas.
- **No push; the browser polls.** Rejected, though it is defensible: 30 rows once a second is nothing, and it works under any topology.

## Consequences

**This is what makes the SQS ↔ RabbitMQ swap survive.** The swap is free for the work queue precisely because fan-out was never asked of it. A future contributor who "simplifies" by moving notifications onto the broker will make the RabbitMQ adapter easy and the SQS adapter impossible.

A `NOTIFY` payload is capped at 8000 bytes, so notifications carry an id and the receiving node re-reads. A dropped notification is not recovered by the transport — it is repaired when the browser reconnects and refetches. That is the correct semantic for a live screen.

**Superseded in one detail by [ADR-0006](./0006-the-read-model-is-fed-by-a-transactional-outbox.md):** the worker does not issue the `NOTIFY`. The outbox relay does, after projecting. Otherwise a notification can overtake the projection and every web node refetches stale data.
