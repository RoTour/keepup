# An Evaluation exists from submission; Release is per-Question and repeatable

The LLM provider will have an outage during somebody's class. If Evaluations only came into existence once grading succeeded, absence would be ambiguous — the Trainer could not tell "still working" from "gave up" from "the message was lost", and neither could the Learner.

So an Evaluation exists from the moment its Submission does, undecided. The LLM proposes a grading, or the attempt is abandoned after retries. **Only graded Evaluations can be released, and releasing can be done again at any moment.** A Trainer whose class is half-graded releases the twenty-four that landed, keeps teaching, and releases the remaining six after the provider recovers and the dead-letter queue is redriven.

## Considered Options

- **An Evaluation exists only once graded; Release requires all of them.** Rejected: a vendor outage blocks the classroom, and the Trainer is forced to hand-grade — at the worst possible moment — exactly the work the LLM was brought in to do.
- **Failures are invisible; Release ships whatever exists.** Rejected: ungraded Learners silently receive nothing, and cannot tell whether they were ignored, their answer was lost, or the system broke. Nor can the Trainer, who is the one facing the raised hand.

## Consequences

Two glossary terms had to widen. **Release** is repeatable, not a single whole-Session act — [ADR-0012](./0012-learners-self-pace-and-release-is-rolling.md) later narrows it further, to one Evaluation at a time. **Override** now means the Trainer's own grading whether or not the LLM proposed one — otherwise a Submission the LLM could not grade could never be graded at all.

A Learner may see feedback on question 2 before question 1, if question 1's grading was abandoned and later recovered. This is accepted.

The recovery story only works while the class is still in the room. Per [ADR-0009](./0009-a-learner-is-a-browser-token-and-a-first-name.md) a Learner's feedback dies with their browser tab, so redriving the dead-letter queue after everyone has dispersed Releases to nobody. For a four-minute outage inside a two-hour class this is nearly always fine — but it is *nearly*, not always.

> Repaired by [ADR-0015](./0015-a-learner-registers-after-their-first-session.md): a registered Learner's released feedback belongs to their account and survives the tab, so a redrive after dispersal now Releases to people who will see it tonight. Only anonymous first-Session participants still lose it.

The number of attempts before an Evaluation is abandoned is a policy of the queue adapter, not of the domain. The domain is told *that* grading was abandoned, never that `ApproximateReceiveCount` exceeded five.
