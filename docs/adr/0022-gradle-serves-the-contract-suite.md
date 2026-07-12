# Gradle serves the contract suite, and JPA serves three aggregates and nothing else

Java 21, Spring Boot, Angular, one monorepo, Postgres: fixed by the product owner, and they need no defence here. Two choices *inside* that stack were made for reasons, and the reasons are the point.

## The build tool was chosen by the project's most important test

[ADR-0008](./0008-both-queue-adapters-are-production-paths.md) says the deliverable is not a second adapter — it is **one contract suite executed twice**, against Testcontainers RabbitMQ and against a real `eu-west-3` SQS queue. Mechanically that is an abstract JUnit class with factory hooks, living in the Delivery module's test source set, consumed as a dependency by two adapter test classes in two different places.

Gradle's `java-test-fixtures` plugin does exactly that, in one line, as a first-class dependency edge the build graph understands. Maven's route is a `test-jar` and a separate shared-test module: it works, and it makes the single most load-bearing test in the project the most awkward thing in the build. **We picked the build tool that makes the ADR-0008 suite ordinary.**

Convention plugins in `build-logic/` (`keepup.java`, `keepup.spring-adapter`, `keepup.archunit`) then give every module identical Java 21, ArchUnit and Testcontainers setup — so ArchUnit is not something a module opts into and can therefore forget to.

## Two persistence idioms, and the line between them is not arbitrary

**Spring Data JPA for exactly three aggregates**: Quiz, the Session snapshot, and Course. These are real trees — Questions holding Criteria, a Session holding frozen SessionQuestions, SessionCriterions and Participants — and cascading a whole graph through one `save` is the one thing an ORM is genuinely good at. Separate persistence entities, hand-written mapping, no MapStruct. **The domain stays annotation-free**: no `jakarta.persistence` import exists inward of an adapter, and ArchUnit fails the build if one appears.

**`JdbcClient` for everything else** — Submissions, Evaluations, the outbox, the projections, every read-side query. The forcing case is a single statement:

```sql
INSERT … ON CONFLICT (submission_id) DO NOTHING
```

That is [ADR-0003](./0003-the-evaluation-queue-is-at-least-once-and-unordered.md)'s unique-constraint backstop — the thing that makes a duplicate delivery harmless, which [ADR-0017](./0017-the-relay-enqueues-the-grading-job.md) then relies on to make duplicate enqueues *normal operation*. It is a Postgres upsert, not an object-graph write. JPA reaches it only through a native query or a merge-and-hope, i.e. through its escape hatch — and an idempotency guarantee routed through an escape hatch is not a guarantee anyone should be asked to trust. Write it as SQL, in the adapter, where ADR-0003 can be read straight off the line.

The read side, for its part, has no aggregate at all ([ADR-0006](./0006-the-read-model-is-fed-by-a-transactional-outbox.md), [ADR-0016](./0016-only-delivery-pays-for-cqrs.md)): a projection is a table shaped for a screen, and an ORM has nothing to offer it.

**Flyway owns the schema; JPA runs `ddl-auto=validate`.** Drift fails the container at boot, loudly, rather than at 09:05 in front of a class.

**Postgres is 15.8 everywhere.** Production is `supabase/postgres:15.8.1.085`; dev compose and Testcontainers both run `postgres:15.8-alpine`. (The plan originally said 17; that was wrong — `docs/WORKFLOW.md` §1.2 is the amendment of record.) This matters more than a version number usually does: [ADR-0005](./0005-work-queue-and-notification-fan-out-are-different-ports.md), ADR-0006 and [ADR-0021](./0021-keepup-connects-to-postgres-directly.md) all rest on `LISTEN/NOTIFY` and advisory locks, so dev, CI and production must be exercising the same engine, not a family resemblance.

## Considered Options

- **Maven.** Rejected on the fixtures point above. Everything else about it is fine.
- **JPA for everything.** Rejected: the Evaluation upsert, and a read model with no aggregates in it paying an ORM's full cost to project rows.
- **`JdbcClient` for everything; no JPA at all.** Rejected, though it is genuinely tempting — it would delete the `ddl-auto` drift risk and the two-idiom seam in one stroke. But Quiz and the Session snapshot are trees, and hand-writing insert/update/delete of a Quiz's Questions and their Criteria, with ordering and orphan removal, is re-implementing the one thing JPA does well, worse. The three aggregates are where JPA pays. Nowhere else is.
- **Annotate the domain directly** — `@Entity` on `Quiz`. Rejected: it puts `jakarta.persistence` inside the hexagon, and it means the aggregate's shape gets negotiated with the ORM. That is how invariants quietly get relaxed to please a mapper.

## Consequences

**A reviewer must know which side of the line they are on.** The rule: an aggregate saved as a tree → JPA; everything else, including everything the relay and the projector touch → `JdbcClient`. ADR-0016 draws a *different* line, between contexts. Both are real, and they are not the same line.

Hand-written mapping is boilerplate, and it is the price of an annotation-free domain. It is the same trade ADR-0020 makes at the context boundary: the tedium is where the boundary becomes something a compiler checks.

**`flush()` before writing an outbox row that carries a generated id.** This is the one place the two idioms meet inside a single transaction, and the one place they bite.

Spring Boot 4.1.0 is very recent. If Flyway, Spring AMQP, AWS SDK v2, Testcontainers or ArchUnit lag it, the fallback is the 3.5.x line. S0.1 verifies this and reports before anything is built on it.
