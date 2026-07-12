# No context imports another, so the crossing lives in the composition root

Authoring, Delivery and Identity are Gradle modules, and none of them depends on another. Only `:backend:app` depends on all three. Acyclicity is therefore a compile-time fact, not a convention — and ArchUnit backs it up at package level, because adapters share a module with the domain they serve and Gradle alone cannot see inside.

But the contexts do need things from each other. Delivery needs a Quiz's Questions to freeze into a Session ([ADR-0001](./0001-session-snapshots-its-quiz.md)). Authoring needs a Username to attribute a public Quiz ([ADR-0014](./0014-a-public-quiz-is-imported-by-copy.md)). Registration spans both ([ADR-0015](./0015-a-learner-registers-after-their-first-session.md)). The pattern has three parts and no exceptions:

1. **A driven port, declared in the consuming context.** `IQuizSnapshotSource` lives in *Delivery*. The consumer states what it needs, in its own vocabulary; the producer does not get to decide the shape of somebody else's dependency. This is the hexagon's usual argument, pointed sideways instead of outward.
2. **Types owned by the consuming context.** `QuizSnapshot` is a Delivery value object. Authoring's `Quiz` aggregate never leaves Authoring. Delivery re-declares `QuizId` and `TrainerId` as its own opaque VOs — there is no shared kernel; identifiers convert at the boundary.
3. **The adapter in `:backend:app`** — the only module allowed to see both sides. It calls the sibling's public query in-process (`GetQuizForRun(quizId, trainerId)`, which enforces Collection ownership on *Authoring's* side, where that rule lives) and maps the result field by field.

**Field-by-field mapping IS the copy.** This is the part that looks like boilerplate and is not. ADR-0001 says the snapshot is the boundary — that editing a Quiz later cannot change what a past Session's Evaluations meant. The mapping loop is where "copy" stops being a sentence in an ADR and becomes something the compiler checks. Hand it to a reflective mapper and the two models are coupled by field name across a boundary that exists to prevent exactly that; the day Authoring renames something, Delivery's snapshot breaks — or, worse, quietly doesn't.

## The three crossings

- **`IQuizSnapshotSource`** — Delivery ← Authoring. `QuizSnapshot fetch(QuizId, TrainerId requester)`: ordered question texts, criterion texts, and the `quizId` for lineage. Called once, at `StartSession`. After that Delivery never reads Authoring again, for the life of the Session or of the record.
- **`ITrainerDirectory`** — Authoring ← Identity. A Username for a `TrainerId`, for public-Quiz attribution. Authoring does not read an account; it reads a name.
- **Registration orchestration** — Delivery ↔ Identity, sequenced in `:backend:app`: read the Course's optional email-domain restriction from Delivery, pass it to Identity's `RegisterLearner` **as a value parameter**, and on verification call Delivery's `ClaimParticipation`. Identity never reads a Course. It is handed a rule, not a place to look one up.

## Considered Options

- **Direct SQL into a sibling's schema.** The read is trivial — Delivery joins Authoring's tables at `StartSession` and is done. Rejected: it couples Delivery to a schema Delivery does not own and cannot see changing. An Authoring migration becomes a breaking change to a context that never imported it, with nothing — not the compiler, not ArchUnit, not a test — standing between the rename and a broken class. Separate schemas with one owning role per database make this hard on purpose.
- **Event-carried state transfer** — Authoring publishes, Delivery keeps a replica. Rejected. It is the right answer when the two sides are separate processes that must not require each other to be up. They are the same process. It buys an availability we already have, and pays in a replica to keep fresh, an ordering problem to solve, and an outbox in a context [ADR-0016](./0016-only-delivery-pays-for-cqrs.md) has just decided will not have one.
- **A shared kernel module** of common ids and types. Rejected: it becomes the place every "just one more shared thing" goes, and the day two contexts disagree about what a `TrainerId` means, the kernel is where that argument is not allowed to happen. `Trainer` already means two different things in Authoring and in Delivery — the CONTEXT-MAP says so — and a shared type would be a standing invitation to forget it.

## Consequences

**`:backend:app` accumulates cross-context adapters and orchestrators, and that is its job.** It is the one place where knowing two contexts is legal. But everything there is wiring or a crossing: the moment a crossing starts making a *decision* — applying a rule that belongs to one side — the rule is in the wrong module.

**An orchestrator has no transaction spanning two contexts.** Physically it could — one process, one database — but a transaction across two contexts is the coupling this ADR removes, re-entered through the back door. So registration is a *sequence*, and it has a window: the orchestrator can crash between `RegisterLearner` and `ClaimParticipation`, leaving a Learner with a verified account whose first Session's work is still anonymous.

**The Claim is retried while the browser token is alive, and that is the whole recovery.** ADR-0015 already bounds the Claim by the token's life, so the window this opens is a window ADR-0015 has already scoped. If the browser dies too, the participation stays anonymous — which is precisely the outcome ADR-0015 states and accepts.

The alternative a future reader will reach for is a **durable claim-intent**: persist the intent, let a relay retry it until it lands. Rejected. It puts outbox-shaped machinery — a table, a drain loop, a cursor, its crash windows — into **Identity**, and [ADR-0016](./0016-only-delivery-pays-for-cqrs.md) has just decided that only Delivery pays for that. Reversing a one-ADR-old decision to close a rare window is a bad trade, and the window is rare: it requires a crash inside the orchestrator's sequence *and* a Learner who then closes the tab.

The residual, stated plainly: **a Learner who registers, is hit by that crash, and closes their tab loses their first Session's feedback.** They keep the account. Every Session after the first is unaffected.

The call is synchronous, and `StartSession` is slower by the cost of one read in another context. It is a read, in the same database, in the same JVM.

**ArchUnit is the proof.** No class under `keepup.authoring.*` imports `keepup.delivery.*` or `keepup.identity.*`, and the same in every other direction. Live from M0, failing the build, before there is any code to violate it.

If a context is ever extracted into its own process, the port does not change — only the adapter does, from a method call to an HTTP client. That is the same claim [ADR-0008](./0008-both-queue-adapters-are-production-paths.md) makes about the broker, and it is worth as much as the discipline that keeps it true.
