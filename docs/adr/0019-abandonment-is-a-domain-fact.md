# Abandonment is a domain fact, and redrive is a use case

[ADR-0003](./0003-the-evaluation-queue-is-at-least-once-and-unordered.md) says the domain never sees a receive count, and [ADR-0004](./0004-an-evaluation-outlives-its-grading-attempt.md) says *abandoned* is a state an Evaluation can be in. This decides where the translation happens, and what recovery looks like on both brokers.

Only the adapter can see the counter — SQS's `ApproximateReceiveCount`, a RabbitMQ quorum queue's `x-delivery-count`. On the **final permitted delivery**, when the count has reached the limit the broker was configured with (`maxReceiveCount`, `delivery-limit`), the adapter does not attempt the grading again. It reports the domain fact **grading abandoned**, and *then* lets the message die: SQS by not deleting it, RabbitMQ by rejecting it to the dead-letter exchange.

That order is the whole thing. If the message dead-lettered without the domain being told, the Evaluation would sit undecided forever and ADR-0004's argument — that absence is ambiguous, that a Trainer must be able to tell *still working* from *gave up* — would be back, unanswered, in the one place it was supposed to be answered. `AbandonGrading` takes an `EvaluationId`. It would take exactly the same argument if the broker were a sheet of paper.

Recovery is `RetryAbandonedGradings`: a Delivery use case that finds the Session's abandoned Evaluations and re-enqueues them through `IEvaluationWorkQueue`. It speaks the port, so it is **the same code on both brokers**. No AWS console, no `StartMessageMoveTask`, no RabbitMQ shovel, no credentials. The Trainer taps *retry* in the app, in front of the class. That is the M3 demo criterion, exactly: revoke the OpenRouter key, watch the Evaluations surface as abandoned, restore it, tap retry, watch them grade.

The state machine this implies, in Delivery's `grading` feature:

- `undecided → proposed | abandoned | overridden`
- **`abandoned → proposed` is legal.** An abandoned Evaluation is not terminal — that transition *is* redrive, and ADR-0004's "release the twenty-four that landed, release the remaining six after the provider recovers" has no meaning without it.
- **`overridden` is terminal against LLM writes.** A grading job for an overridden Evaluation — a duplicate, a redrive, a slow worker returning after the Trainer lost patience — is acknowledged and dropped, never written. That is [ADR-0002](./0002-the-llm-proposes-the-trainer-releases.md)'s authority, enforced at the last possible moment.

Two retry budgets exist and they are not the same thing. The LLM adapter retries a malformed tool call **once** in-process ([ADR-0007](./0007-a-verdict-must-quote-the-learners-own-words.md)); the broker has a delivery budget measured in redeliveries. They fail into the same domain fact, and neither knows about the other.

## Considered Options

- **Let the broker's dead-letter queue be the recovery mechanism** — redrive from the AWS console, or a shovel on RabbitMQ. Rejected on two counts. The two procedures are not the same operation, so [ADR-0008](./0008-both-queue-adapters-are-production-paths.md)'s interchangeability claim would quietly expire at the first failure, which is the first moment anyone would check. And the person who needs the recovery is a Trainer standing in front of thirty people, not an operator with an AWS login.
- **Retry forever; never abandon.** Rejected: a poison Submission — or a revoked API key — regrades until the class ends, and the Trainer cannot distinguish it from work in progress. ADR-0004 exists to make that distinction possible.
- **Let the domain read the receive count and decide when to give up.** Rejected: the number and its semantics differ per broker and per queue configuration. The instant a use case branches on it, the adapters stop being interchangeable and ADR-0003's rule is dead — without a single line of the port changing.

## Consequences

**The dead-letter queue becomes a diagnostic, not a control plane.** It still exists, still fills, and Terraform still provisions it — SQS's redrive policy is *how the delivery budget is expressed*, so it is load-bearing whether or not anyone ever reads from it.

Both adapters must be configured so the give-up threshold is reachable and cheap to reach in a test. The ADR-0008 contract suite asserts *attempt exhaustion produces exactly one "grading abandoned" fact*, on both brokers, against a short-visibility test queue. **That assertion is what makes this ADR true rather than aspirational.**

*Exactly one* is a real constraint: an at-least-once queue can deliver the final attempt twice. `AbandonGrading` must be idempotent for the same reason `ProposeEvaluation` is, and its second call must not un-propose an Evaluation that a concurrent redrive has already graded.

**`RetryAbandonedGradings` is Trainer-triggered, and only Trainer-triggered.** There is no scheduled sweep. It is a Trainer-facing act on a Trainer-facing screen, and that is the same shape as everything else here: [ADR-0002](./0002-the-llm-proposes-the-trainer-releases.md) says the LLM proposes and the Trainer decides, and *decide to try again* is a decision like any other.

The alternative — a relay job that sweeps abandoned Evaluations automatically — is rejected on its bad case, which is not rare. Gradings are abandoned in bulk exactly when the provider is down, and a sweep would then hammer a provider that is *still* down, mid-class, burning the OpenRouter budget against an outage it cannot fix. The one who knows whether another attempt is worth anything is the person standing in the room, and they already have a button.

Nothing is closed off. An automatic backoff sweep would call the same use case, unchanged; it needs only a backoff policy and a cap on attempts, and it can be added the day someone wants it. **It is not built.**
