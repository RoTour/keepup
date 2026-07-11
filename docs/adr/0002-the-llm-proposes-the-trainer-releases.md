# The LLM proposes an Evaluation; the Trainer releases it

An LLM grading free text against a Criterion will sometimes mark a correct answer wrong — a Learner who phrases the right idea in unexpected vocabulary is the common case, not the rare one. We are unwilling to let a machine tell a student they are wrong with no human in the loop. So an Evaluation produced by the LLM is a *proposal*: it is visible only to the Trainer until the Trainer releases that Question's Evaluations to its Learners.

Review is a triage, not a re-grading. Proposals land continuously on the Trainer's screen as Learners answer, their attention goes to the outliers, they Override the ones that are wrong, and a single action releases everything currently shown. A Trainer glances at the feed a handful of times per Session — not once per answer.

> Amended by [ADR-0012](./0012-learners-self-pace-and-release-is-rolling.md). Release was originally a per-Question act taken once, after the Question closed. Learners self-pace, so it became a rolling per-Evaluation act. The bulk action is what preserves the argument above.

## Considered Options

- **The LLM's grade is a verdict; the Trainer overrides afterwards.** Rejected: the hallucinated "wrong" reaches the Learner before any human has seen it, and retracting feedback someone already read is worse than delaying it. It also does not save the Trainer any work — to find the one bad verdict they must still read all thirty.
- **The LLM's grade is final; no override.** Rejected: the Trainer authored the Criteria and is the expert in the room. A model that removes their authority over the grade contradicts the reason they are using the tool.

## Consequences

The Trainer's read model is *upstream* of the Learner's, not parallel to it. The two views are sequential stages of one flow, which is what keeps "both audiences are first class" from doubling the work.

A Trainer who never clicks Release leaves the class with no feedback at all. [ADR-0010](./0010-ending-a-session-forces-a-decision.md) resolves what happens at the end of a Session: ending it is blocked until every Question's graded Evaluations are Released or explicitly Discarded.

"Publish" is not used for this act. The message queue publishes messages; overloading the word across the domain and the transport would be a mistake.
