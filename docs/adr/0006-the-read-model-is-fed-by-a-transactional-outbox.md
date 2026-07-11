# The read model is fed by a transactional outbox, not by the broker

Commands go through the Session aggregate. Queries read purpose-built tables that no aggregate is ever loaded to serve. The read model is eventually consistent, maintained by a projector — the write path does not know it exists.

Domain events reach that projector through an **outbox table written in the command's own transaction**, drained in `seq` order by a single relay which projects, then notifies, then marks the row published. They do not travel over SQS or RabbitMQ.

## Why not the broker, when we already run one

Two reasons, and both are bugs we have already fixed once.

**Ordering.** [ADR-0003](./0003-the-evaluation-queue-is-at-least-once-and-unordered.md) establishes that the broker is unordered. Two independent messages, `EvaluationProposed` and `EvaluationOverridden`, owe each other nothing. If the override is projected first and the proposal lands afterwards, the read model overwrites ✓ with ✗ and the Trainer's Override vanishes from the only place anybody looks — while the write model remains perfectly correct. An outbox `seq` is a single monotonic sequence read by a single loop, so the order is the order.

**Dual write.** Committing the Evaluation and then publishing to a broker are two operations against two systems with no transaction between them. Crash in the gap and the event is gone permanently — and the retry cannot help, because ADR-0003's idempotency check sees the Evaluation already exists and correctly does nothing. The screen stays blank forever. Writing the event *as a row, in the same transaction as the state it describes* is the only thing that closes that window.

Delivery from the outbox is still at-least-once: the relay can crash after projecting and before marking published. The projector absorbs replays with a last-applied `seq` cursor — the read-side twin of "a Submission has at most one Evaluation."

## Considered Options

- **Publish domain events on the message broker.** Rejected for the two reasons above.
- **Project synchronously inside the command's transaction.** Rejected, though it is the cheapest correct option and needs no outbox, no relay and no cursor. It couples the write path to every read model, and forgoes the event-driven design this project exists to explore. The workload does not justify eventual consistency; the learning goal does. That is the honest reason.

## Consequences

The relay is the only thing that notifies. [ADR-0005](./0005-work-queue-and-notification-fan-out-are-different-ports.md) said the worker writes and then notifies; that would let a `NOTIFY` outrun the projection and cause web nodes to reliably refetch stale data. One relay, projecting then notifying, in `seq` order, removes the race.

The Trainer's Override lags the read model. The command's HTTP response carries the new state so Angular renders it immediately; the push arrives milliseconds later to confirm what the screen already shows. **This is a real cost of the choice, not an oversight.**

The relay is a single point of serialisation, and the outbox grows and needs pruning. Neither matters at one classroom.

Describing this system as "CQRS" without qualification invites the question *"quel est votre read store?"* — the answer is a set of projected tables in the same Postgres, and the interesting part is the outbox, not the store.
