# The relay enqueues the grading job, and the outbox is appended under a lock

`SubmitAnswer` writes three things in one transaction: the Submission, its undecided Evaluation, and a `SubmissionReceived` outbox row. The tempting fourth line — `workQueue.enqueue(...)` at the end of the command handler — is the bug this ADR exists to forbid.

It is a dual write, the same one [ADR-0006](./0006-the-read-model-is-fed-by-a-transactional-outbox.md) refused, and it fails worse. Commit succeeds; the process dies before the enqueue; there is now a Submission with an undecided Evaluation that **no worker will ever be handed**. Nothing retries it, because nothing knows it exists. And [ADR-0003](./0003-the-evaluation-queue-is-at-least-once-and-unordered.md)'s idempotency cannot repair it: idempotency makes a message delivered twice harmless. It has nothing whatsoever to say about a message that was never sent. The Learner waits for feedback with no producer, and the Trainer sees an Evaluation stuck undecided with no failure to point at.

So **the relay enqueues.** Draining a `SubmissionReceived` row, it enqueues to `IEvaluationWorkQueue`, projects, notifies, and only then marks the row published. The order is not incidental. A crash between the enqueue and the mark replays the row on restart and enqueues the job a second time — which is precisely the duplicate ADR-0003's contract absorbs by construction, at a cost of at most one wasted LLM call, already accepted there.

That is the trade, stated plainly: **we accept a window that duplicates work, to close a window that loses it.** The relay is already the single writer of the read model; it is now the single door out of a command transaction, and there is no other.

## A `bigserial` is not commit order

The relay drains `WHERE seq > cursor ORDER BY seq` and advances a strictly ascending cursor. That is correct only if `seq` order is commit order. **It is not.**

`bigserial` assigns at `INSERT`, not at `COMMIT`. Transaction A appends its outbox row and takes seq 5. Transaction B appends and takes seq 6. B commits first. The relay wakes, sees 6, drains it, sets the cursor to 6 — and *then* A commits. Row 5 becomes visible **below** a forward-only cursor that will never look back.

Row 5 is skipped for the lifetime of the system. Its grading job is never enqueued; its Evaluation stays undecided forever; its projection never lands. There is no error, no dead letter, no retry, no log line. One Learner's answer is simply never graded, and nothing in the system is capable of noticing.

The fix is one line in the outbox writer: take `pg_advisory_xact_lock` on a fixed key **before appending**, inside the command's own transaction. Concurrent appenders serialise; the lock is held to commit; so the transaction that takes the lower `seq` is the transaction that commits first. `seq` order becomes commit order, which is what the cursor already assumed it was.

**Do not remove this lock.** It reads like a bottleneck and is not one. It serialises only the tail of the transactions that append — so append last, and keep the command short. A classroom is thirty Learners submitting a handful of answers each over an hour: order a hundred appends, contending for microseconds. The cost is nil, and it is nil for reasons that will not change while this is a classroom app.

Anyone who profiles the write path, finds the lock, and takes it out will measure an improvement. Weeks later, one Learner will be ungraded and there will be no trace of why. If you have found a cheaper way to make `seq` mean commit order, you have almost certainly found this bug again.

## Considered Options

- **Enqueue from the command handler, after commit.** Rejected: the dual write above. Its failure is silent, permanent, and unrepairable by any retry the system is capable of.
- **Mark published, then enqueue.** Rejected without ceremony: it converts a duplicate into a loss, which is the wrong direction on the only axis that matters.
- **A gap-tolerant cursor** — re-scan a window below the high-water mark for rows that arrived late. Rejected: it replaces a guarantee with a heuristic, and the heuristic is a bet on the longest transaction you have never seen. It is also more code, and more crash windows to spec, than the lock.

## Consequences

**Duplicate enqueues are normal operation, not an incident.** The RabbitMQ management UI may show two jobs for one Submission after a relay restart. `ProposeEvaluation` is idempotent (ADR-0003), the unique constraint on `submissionId` is the backstop, and the second job's worker acknowledges and does nothing. The relay's specs must exercise this deliberately: replay after crash, crash mid-batch, duplicate enqueue tolerated.

**The relay is now on the critical path of grading, not only of the screen.** If the relay is down, submissions still land and Evaluations still exist — but nothing is graded until it comes back. It catches up from the cursor, in order, and nothing is lost. This is the acceptable form of the failure, and it is why the relay's singleton lock ([ADR-0021](./0021-keepup-connects-to-postgres-directly.md)) and its ordering lock are two different mechanisms that must both hold.

Grading latency now includes the relay's poll interval. At classroom scale that is noise against an eight-second LLM call.

The lock key is a constant, and it is per-outbox, not per-Session. Serialising only within a Session would be faster and would restore the exact bug: the cursor is global, so the ordering guarantee must be global too.
