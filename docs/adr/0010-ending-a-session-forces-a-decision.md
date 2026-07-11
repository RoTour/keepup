# Ending a Session forces a decision on unreleased Evaluations

Ending a Session is a deliberate act, and the Trainer cannot complete it while a Question still holds graded Evaluations nobody has seen. They must Release them or explicitly Discard them. A Trainer who instead closes their laptop and walks away loses everything: the Session expires after 24 hours having released nothing.

Grading already in flight runs to completion after the Session ends. The record stays complete even though, per [ADR-0009](./0009-a-learner-is-a-browser-token-and-a-first-name.md), there is no longer anybody in the room to Release it to.

## Considered Options

- **Ending auto-releases every decided Evaluation.** Rejected, and it is the tempting answer — no Trainer ever forgets, nobody loses feedback. But it pushes thirty unreviewed LLM proposals to thirty students because a human had a train to catch. It inverts [ADR-0002](./0002-the-llm-proposes-the-trainer-releases.md): releasing becomes the default and the Trainer's authority over a grade becomes the thing they must remember to opt into.
- **A Session never ends; it merely expires.** Rejected. It is the most honest model of how trainers actually behave — they close laptops, they do not click "End session" — and it silently discards thirty people's feedback while telling nobody. Learners' tabs would sit open awaiting a Release that is never coming.

## Consequences

**Discard is a first-class act, not an absence.** A Trainer who decides the LLM's proposals for question 3 are worthless says so, and the system records that they said so. Discarding is a decision; forgetting is not.

The Trainer meets a modal at the end of class, when everyone is already putting their coats on. This friction is the point: it is the last moment at which the human gate can be exercised.

A Trainer who abandons a Session still loses everything. Expiry is the fallback for walking away, not a supported path.
