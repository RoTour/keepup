# A Verdict is binary and must quote the Learner's own words

An Evaluation holds exactly one Verdict per Criterion: met, or not met. A Verdict of *met* must carry Evidence — the span of the Submission that satisfies the Criterion, quoted verbatim. A Verdict of *not met* carries none.

The Trainer has twenty seconds and thirty answers. Triage is only possible if a proposal can be scanned rather than read. Thirty short quotes can be scanned; thirty paragraphs cannot, and a Trainer who must read every answer is doing by hand the work the LLM was brought in to do.

Evidence is not decoration. It is what makes a hallucination **visible**: a fabricated *met* has either no supporting span or an irrelevant one, and the Trainer sees that in half a second without reading the answer. It also plays to the model's strengths — grounded binary classification is a task LLMs do reliably, and holistic scoring is one they do badly.

## Considered Options

- **Per-Criterion partial score (0–5).** Rejected. Nothing distinguishes a 3 from a 4, so the Trainer and the model disagree on every answer. Override stops being a click and becomes a slider. The triage screen loses its aggregate: "mean 3.2/5" tells a Trainer nothing they can act on in the next minute.
- **One holistic score plus free-text feedback.** Rejected. It discards the structure the Trainer authored, leaves nothing to aggregate — so the Trainer can never see "the class missed criterion 2", the one fact this product exists to surface — and contradicts the glossary's rule that a Question is graded against its Criteria and nothing else.

## Consequences

**No partial credit.** An answer that nearly addressed a Criterion is marked not met. This is a real loss and the Trainer's Override is the remedy.

**Evidence is verifiable by the adapter, not just by the Trainer.** Because the quote must be verbatim, the `ILlmGrader` adapter can check mechanically that the Evidence appears in the Submission (after whitespace and case normalisation) before it ever constructs a domain object. A model that paraphrases has failed the contract.

The port returns a domain type. The adapter validates that there is exactly one Verdict per Criterion, that the Criterion identifiers match the Session's frozen copy, and that every *met* carries locatable Evidence. Non-conforming output is retried once and then abandoned, which lands the Evaluation in the abandoned state of [ADR-0004](./0004-an-evaluation-outlives-its-grading-attempt.md). No provider type crosses the port boundary.

A false *not met* has no Evidence to inspect, so the Trainer cannot spot it by scanning. Catching those still requires reading the answer. The asymmetry is accepted: a wrongly-generous grade is caught cheaply, a wrongly-harsh one is not.
