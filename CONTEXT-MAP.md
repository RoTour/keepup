# Context Map

## Contexts

- [Authoring](./docs/contexts/authoring/CONTEXT.md) — a Trainer writes open-ended questions and states what a good answer must contain
- [Delivery](./docs/contexts/delivery/CONTEXT.md) — a Quiz is run live with an audience: answers are collected, graded, and released
- [Identity](./docs/contexts/identity/CONTEXT.md) — *supporting*: owns the accounts. Trainers are provisioned (no signup); Learners self-register, deferred until after their first Session. Issues `TrainerId` and `LearnerAccountId`

## Relationships

- **Authoring → Delivery**: starting a Session copies the Quiz's Questions and Criteria into the Session. That copy is the boundary. Delivery never reads Authoring at runtime, and editing a Quiz later cannot change what a past Session's Evaluations meant. See [ADR-0001](./docs/adr/0001-session-snapshots-its-quiz.md).
- **Authoring ↔ Delivery**: identity only — `TrainerId`, `QuizId`. No entity crosses the boundary. The crossing is a driven port in the *consuming* context (`IQuizSnapshotSource`, owned by Delivery), whose adapter lives in `:backend:app` and maps field by field. See [ADR-0020](./docs/adr/0020-no-context-imports-another.md).
- **Identity → Authoring, Identity → Delivery**: identity only — `TrainerId` minted at Provisioning, `LearnerAccountId` minted at Registration. Neither context ever reads an account; a Trainer renaming their Username changes nothing outside Identity. The one exception is a name, not an account: `ITrainerDirectory` (Authoring ← Identity) resolves a Username for public-Quiz attribution, by the same pattern — [ADR-0020](./docs/adr/0020-no-context-imports-another.md).
- **Delivery ↔ Identity at Registration**: the prompt fires from inside a Session, the new account must satisfy the Course's domain restriction, and the Claim binds a Session participation to the account — identifiers cross, entities never do. See [ADR-0015](./docs/adr/0015-a-learner-registers-after-their-first-session.md). The sequence is orchestrated in `:backend:app`; Identity is *handed* the domain restriction as a value and never reads a Course — [ADR-0020](./docs/adr/0020-no-context-imports-another.md).
- **`Trainer` is defined in both business contexts, and does not mean the same thing.** In Authoring a Trainer is an author. In Delivery a Trainer is the authority over a grade. Both roles are backed by one Trainer Account in Identity.
- **Grading is not a context.** The LLM lives behind a driven port inside Delivery, because every meaningful state of an Evaluation — proposed, overridden, released — is a Trainer act. See [ADR-0002](./docs/adr/0002-the-llm-proposes-the-trainer-releases.md).

## Layout

These glossaries live under `docs/contexts/` until the module layout exists, then they move next to their packages. ADRs are numbered globally in `docs/adr/`; with two contexts, per-context numbering buys nothing.
