# The evaluation queue's contract is at-least-once and unordered

We want to run either AWS SQS or RabbitMQ behind the same port, with no change to the domain. Both guarantee at-least-once delivery; neither guarantees exactly-once. So the domain assumes the intersection: **a Submission may be handed to the grader more than once, and messages may arrive in any order.**

The invariant that makes this safe: **a Submission has at most one Evaluation.** `ProposeEvaluation` is idempotent — if the Submission already has an Evaluation, it acknowledges the message and does nothing. A unique constraint on `submissionId` is the backstop. As a best effort, the worker checks for an existing Evaluation before calling the LLM, so a duplicate usually costs no tokens.

## Considered Options

- **Last write wins.** Rejected. SQS's visibility timeout expires while a slow LLM call is still running; a second worker grades the same Submission. Meanwhile the Trainer has already Overridden the first result. The second write lands and destroys the Override — the exact authority [ADR-0002](./0002-the-llm-proposes-the-trainer-releases.md) exists to protect. Because the LLM samples, the two gradings genuinely differ.
- **Lean on broker deduplication.** SQS FIFO content-based dedup, or RabbitMQ's dedup plugin. Rejected. It makes correctness depend on which broker is running, which is precisely the coupling this project set out to avoid. It also trades one vendor lock-in for two, caps SQS FIFO at 300 msg/s, and its 5-minute dedup window is shorter than a real outage — so it is not even exactly-once.

## Consequences

**Portability lives in the semantic contract, not in the interface.** A port with `enqueue()` on it is trivially implementable by both brokers and proves nothing. What the swap actually rests on is the domain never assuming ordering or single delivery. A future contributor who "optimises" by enabling FIFO deduplication has silently ended the portability without touching a single line of the port.

A duplicate delivery may cost one wasted LLM call. That is accepted.

Broker-specific give-up signals — SQS's `ApproximateReceiveCount`, RabbitMQ's `x-death` header — must be translated by the adapter into a domain fact. The domain never sees a receive count.
