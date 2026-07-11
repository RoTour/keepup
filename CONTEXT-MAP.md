# Context Map

## Contexts

- [Authoring](./docs/contexts/authoring/CONTEXT.md) — a Trainer writes open-ended questions and states what a good answer must contain
- [Delivery](./docs/contexts/delivery/CONTEXT.md) — a Quiz is run live with an audience: answers are collected, graded, and released

## Relationships

- **Authoring → Delivery**: starting a Session copies the Quiz's Questions and Criteria into the Session. That copy is the boundary. Delivery never reads Authoring at runtime, and editing a Quiz later cannot change what a past Session's Evaluations meant. See [ADR-0001](./docs/adr/0001-session-snapshots-its-quiz.md).
- **Authoring ↔ Delivery**: identity only — `TrainerId`, `QuizId`. No entity crosses the boundary.
- **`Trainer` is defined in both contexts, and does not mean the same thing.** In Authoring a Trainer is an author. In Delivery a Trainer is the authority over a grade.
- **Grading is not a context.** The LLM lives behind a driven port inside Delivery, because every meaningful state of an Evaluation — proposed, overridden, released — is a Trainer act. See [ADR-0002](./docs/adr/0002-the-llm-proposes-the-trainer-releases.md).

## Layout

These glossaries live under `docs/contexts/` until the module layout exists, then they move next to their packages. ADRs are numbered globally in `docs/adr/`; with two contexts, per-context numbering buys nothing.
