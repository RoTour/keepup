# Only Delivery pays for CQRS

[ADR-0006](./0006-the-read-model-is-fed-by-a-transactional-outbox.md) buys a transactional outbox, a single relay, a projector and a `seq` cursor. That machinery is **Delivery's**, and it stops at Delivery's border. Authoring and Identity keep their aggregates and read their own tables with plain transactional queries inside the request. No outbox, no projections, no eventual consistency, anywhere but Delivery.

The port is named `IDeliveryOutbox`, not `IOutbox`. That is the decision, spelled in a type name.

## Why Delivery is different, and the other two are not

Delivery is the only context where three roles write concurrently to state that a fourth party is watching live: a Learner submits, a worker proposes a grading, a Trainer Overrides — and a triage screen must show all of it as it happens, to a browser held by a node that did not do any of the writing. ADR-0006's two arguments, ordering and the dual write, are arguments *about that fan-in*. They have no purchase anywhere else.

In Authoring, a Trainer edits their own Quiz, alone, and reads it back. Nothing races. The write **is** the read, and the transaction that made it is still open. A quiz editor that shows you your own edit *eventually* is not an architecture, it is a bug — and the cheapest way to guarantee it never becomes one is to read the row you just wrote, in the transaction you just wrote it in.

In Identity it is starker still: an account is read at login and essentially never again.

## Considered Options

- **CQRS everywhere, for symmetry.** Rejected. Three outboxes, three relays, three cursors, three sets of crash-window specs — to serve two contexts whose read screens are a list of quizzes and a login. Symmetry is not a requirement; it is a feeling. The cost is real machinery and the benefit is that the diagram looks tidy.
- **CQRS nowhere — project synchronously in the command's transaction.** Rejected in [ADR-0006](./0006-the-read-model-is-fed-by-a-transactional-outbox.md), on the honest ground that the workload does not justify eventual consistency but the learning goal does. That reasoning applies to Delivery. It does not generalise into contexts that have no live screen to feed.

## Consequences

**Two persistence idioms live in one codebase, deliberately.** JPA aggregates plus `JdbcClient` reads in Authoring and Identity; aggregates, outbox, relay and projections in Delivery. A reviewer who "harmonises" them will either impose an outbox on a quiz editor or strip the outbox from the only place that needed one. Neither is a cleanup.

Consistency guarantees therefore differ by context, and that is the point. A Trainer's quiz edit is read-your-writes. A Trainer's Release lags the read model by milliseconds (ADR-0006, mitigated by the command response carrying the new state). Different situations, different guarantees.

The `platform` module hosts the outbox relay, the `LISTEN/NOTIFY` plumbing and the advisory-lock helpers as infrastructure with zero domain knowledge — so it *could* serve another context. Today exactly one context calls it, and no other context is entitled to assume it will.

If Authoring ever grows a screen that reads across aggregates and must update live, adding an outbox there is additive and this ADR is amended. It is not a reason to build one now.
