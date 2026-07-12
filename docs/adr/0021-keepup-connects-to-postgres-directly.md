# keepup connects to Postgres directly, and never through the pooler

The production VPS runs a Supabase stack, and its Postgres is fronted by **Supavisor** in transaction mode on port 6543. It is already running, it is free, and it is connection pooling — the single most tempting misconfiguration available to this project. Host port `5432` maps straight through to the `supabase-db` container, so the direct path exists and costs nothing to take.

**keepup's `DATABASE_URL` always targets Postgres directly: 5432, session mode, for every role — `web`, `worker`, `relay`, `migrate`. Supavisor is forbidden.**

Two things keepup does require a connection that belongs to it for longer than a single statement, and a transaction-mode pooler destroys both.

**`LISTEN/NOTIFY`.** [ADR-0005](./0005-work-queue-and-notification-fan-out-are-different-ports.md) puts the notification fan-out on a Postgres channel; [ADR-0006](./0006-the-read-model-is-fed-by-a-transactional-outbox.md) makes the relay the only thing that issues `NOTIFY`. A `LISTEN` registers interest **on a connection**. In transaction mode, the pooler hands that server connection to somebody else's transaction the moment yours ends — and the subscription goes with it. The web node stays connected. It stays healthy. Its health check stays green. It simply never hears anything again.

**Session-level advisory locks.** Exactly one relay may drain the outbox, and what holds that to one is a *session*-level `pg_advisory_lock` held for the life of the process. Through a transaction-mode pooler, "for the life of the session" collapses to "until this transaction ends" — which is immediately. Every relay replica then acquires the lock, every replica believes it is the singleton, and they drain the outbox concurrently. ADR-0006's single-relay ordering guarantee is gone, and the read model is what pays. (Note that [ADR-0017](./0017-the-relay-enqueues-the-grading-job.md)'s `pg_advisory_xact_lock` is transaction-scoped and *would* survive the pooler. It would be the last correct thing left, guarding an ordering that nothing is left to honour.)

**The failure mode is not an error. It is nothing happening.** No exception. No failed health check. No dead letter, no retry, no log line. The triage screen stops updating; the relay quietly multiplies. It is discovered mid-class, from the front of a room, by the one person in the building who cannot debug it. A pooler misconfiguration that *crashed* would be a footnote in this document. This one gets an ADR because it is silent.

## Considered Options

- **Point everything at Supavisor (6543).** Rejected: the two silent failures above, both discovered at the worst possible moment, neither producing a signal anybody could act on.
- **Split it — `relay` and `web` go direct, `worker` goes through the pooler.** Rejected, and it is the dangerous option because it is *correct today*. Roles are one environment variable (`KEEPUP_ROLES`), and moving a duty between roles is a supported operation. A per-role exception is a rule that quietly stops being true the first time somebody rebalances the compose file. One rule, no exceptions, is the only rule that survives that.
- **A session-mode pooler instead of a transaction-mode one.** Rejected: session mode pins a server connection to a client for its whole life, which preserves both behaviours by abandoning the pooling that made a pooler attractive in the first place. It buys nothing over the direct path, and it adds a component that a future operator can flip back into transaction mode without reading this file.
- **Move the fan-out onto RabbitMQ so the pooler stops mattering.** Rejected here, and already rejected by ADR-0005 for an entirely independent reason (fan-out on the broker is what would break the SQS adapter). It also does not work: the relay's singleton lock still needs a session, so the pooler is still forbidden and the shortcut has bought nothing.

## Consequences

keepup gets no benefit from Supabase's pooling and needs none. `web ×2 + worker + relay` with small Hikari pools is tens of connections against a Postgres whose limit is in the hundreds. The problem a pooler solves is not a problem this system has.

**The same hazard exists in miniature inside the app, and has the same shape of answer.** Hikari resets connections on return, so it would drop a `LISTEN` too — which is why the listening connection is a dedicated raw `PgConnection` outside the pool, polling in a loop, reconnecting with backoff and pushing a resync. Anything that recycles a connection underneath keepup breaks keepup. The pooler is that, one layer up.

`scripts/db-tunnel.sh` forwards remote 5432 for this reason and must never be "fixed" to point at the pooler.

**Nothing in the code enforces this.** It is one environment variable in Coolify, set by a human, and the system will start happily if it is wrong. That is precisely why the rule is written here and in `docs/WORKFLOW.md` §1.1 in this much detail: the enforcement is that somebody read it.

If keepup ever genuinely needs a pooler, the two things that break are known and enumerable — move the relay singleton onto a different primitive, and move the notification fan-out off the database. That is a redesign of ADR-0005, ADR-0006 and the relay. Anyone proposing the URL change is proposing that redesign, whether or not they know it.
