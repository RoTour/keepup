# keepup — Implementation Plan

> Written 2026-07-12, at the close of the product-design phase. This document is self-contained:
> a brand-new session should be able to start implementing from it, with the ADRs and context
> glossaries as the requirements source of truth. When this plan and an ADR disagree, the ADR wins;
> when code and this plan disagree, update whichever is wrong — deliberately.

## How to use this document

1. Read `CONTEXT-MAP.md` and the three glossaries (`docs/contexts/{authoring,delivery,identity}/CONTEXT.md`).
2. Skim the ADR index below; read any ADR in full before building the component it governs.
3. Execute milestones in order (M0 → M8). Within a milestone, follow the build order given.
4. Build **one component at a time** using the house cadence (§6). Spec before implementation.
   Validate (`/test`, `/review`) before `/commit`. Never bulk-generate.

## 1. What we are building

A classroom quiz application. A **Trainer** authors Quizzes of open-ended Questions, each with
grading **Criteria** (Authoring). A **Session** runs one Quiz live: **Learners** join with a
**Join Code**, self-pace through open Questions, and submit free-text answers. An LLM proposes a
binary per-Criterion **Verdict** with verbatim **Evidence**; the Trainer triages, **Overrides**,
**Releases** (rolling, per-Evaluation, with a bulk action) or **Discards** (Delivery). A **Course**
groups Sessions across weeks; Learners register an account (deferred, after their first Session)
so the Trainer gets a longitudinal radar and Learners keep their feedback (Identity, supporting).

### ADR index (0001–0015 are decided product/architecture facts; 0016–0023 were written in M0, slice S0.7)

| ADR | Decision |
|-----|----------|
| 0001 | Starting a Session copies the Quiz's questions/criteria into it; grading only ever reads the frozen copy |
| 0002 | The LLM proposes an Evaluation; only the Trainer releases it; review is triage, not re-grading |
| 0003 | Work-queue contract is at-least-once + unordered; `ProposeEvaluation` idempotent; unique constraint on `submissionId` |
| 0004 | Evaluation exists from submission (undecided); abandoned-after-retries is a state; release is repeatable |
| 0005 | Two ports: `IEvaluationWorkQueue` (competing consumers, SQS/RabbitMQ) and `ISessionNotifier` (fan-out, Postgres LISTEN/NOTIFY, id-only payload, refetch) |
| 0006 | Read model fed by transactional outbox; single relay drains in seq order: project → notify → mark published; projector idempotent via seq cursor |
| 0007 | Verdict is binary; *met* requires verbatim Evidence, mechanically validated by the adapter; non-conforming LLM output retried once then abandoned |
| 0008 | Both queue adapters are production paths; `KEEPUP_QUEUE` env flips them; ONE contract suite runs against Testcontainers RabbitMQ AND a real eu-west-3 SQS queue; Terraform provisions SQS |
| 0009 | (Superseded in part by 0015) Learner joins with token + declared first name; Join Code is the entire access control; first minute stays signup-free |
| 0010 | Ending a Session is blocked until every graded Evaluation is Released or Discarded; abandoned sessions expire after 24 h releasing nothing |
| 0011 | Prompt injection contained, not prevented: criteria in system prompt, submission delimited untrusted, forced structured tool call, ONE submission per LLM call, identical-evidence anomaly flagged |
| 0012 | Learners self-pace; Release is rolling per-Evaluation with bulk action; Close ends answering AND reveals Criteria; read model needs coverage denominators |
| 0013 | Trainers are provisioned (no signup): username + password (no email), server-side session cookie; Operator resets passwords out-of-band |
| 0014 | Quiz sharing: Share/Public/Import — import is a full copy owned by the importer; lineage id only; un-share never touches copies |
| 0015 | Learner Accounts via deferred registration: anonymous first Session, then verified school email + password; one-Session grace per Course; optional per-Course email-domain restriction; Claim binds the token's work to the account (token-lifetime window); released feedback survives with the account |
| 0016 | CQRS-lite is Delivery-only: outbox, relay and projections stop at Delivery's border; Authoring and Identity use aggregates + plain transactional reads off their own tables |
| 0017 | The relay enqueues the grading job while draining `SubmissionReceived` (enqueueing from the command handler is an unrepairable dual write); outbox appends take `pg_advisory_xact_lock` so `seq` order is commit order — do not remove the lock |
| 0018 | Web session in Postgres via Spring Session JDBC from M0 (a cookie valid on any node is what makes web×N work); WebSocket handshake authenticated by cookie, or by opaque token for anonymous Learners; CSRF cookie token for Angular; no JWT |
| 0019 | Abandonment is a domain fact reported by the adapter on the final delivery attempt (the domain never sees a receive count); redrive is `RetryAbandonedGradings`, identical on both brokers, no AWS console; `undecided → proposed \| abandoned \| overridden`, `abandoned → proposed` legal, `overridden` terminal vs LLM writes |
| 0020 | Cross-context calls: driven port in the *consuming* context returning context-owned VOs, adapter in `:backend:app`, field-by-field mapping IS the copy; no entity crosses; ArchUnit proves no context imports another |
| 0021 | keepup connects to Postgres directly (5432, session mode), never through Supavisor — a transaction-mode pooler silently kills `LISTEN/NOTIFY` and session-level advisory locks, and the failure mode is *nothing happening* |
| 0022 | Backend stack (§2): Gradle over Maven because `java-test-fixtures` hosts the ADR-0008 contract suite; JPA for exactly three deep aggregates with hand-written mapping (annotation-free domain); `JdbcClient` everywhere else because of `ON CONFLICT DO NOTHING`; Flyway owns the schema, JPA `validate`; Postgres 15.8 |
| 0023 | LLM provider binding: OpenRouter behind `ILlmGrader`, no provider type crosses; the adapter is where ADR-0011's containment, ADR-0007's verbatim-evidence validation and forced tool-calling all land; provider swapping is a live possibility, which is why the port exists |

## 2. Stack (fixed — decided by the product owner)

- **Backend**: Java 21, Spring Boot (latest stable). **Frontend**: Angular. **Single monorepo.**
- **Build**: Gradle (Kotlin DSL). Chosen over Maven because `java-test-fixtures` cleanly hosts the
  ADR-0008 abstract contract suite consumed by two adapter test classes, and convention plugins in
  `build-logic/` give every module identical Java 21 + ArchUnit + Testcontainers setup.
- **Persistence**: Spring Data JPA **only** for the three deep aggregates (Quiz, Session snapshot,
  Course) using separate persistence entities + hand-written mapping (domain stays annotation-free).
  **JdbcClient for everything else**: Submissions/Evaluations, outbox, projections, all read-side
  queries. Flyway owns the schema; JPA runs `ddl-auto=validate`. Rationale: Evaluation writes need
  `INSERT … ON CONFLICT (submission_id) DO NOTHING` (ADR-0003's backstop), which JPA does awkwardly.
- **Queue adapters**: Spring AMQP (RabbitMQ) and AWS SDK v2 (SQS), both behind `IEvaluationWorkQueue`.
- **LLM**: OpenRouter (OpenAI-compatible chat completions) behind `ILlmGrader`.
- **Email**: provider-agnostic SMTP via Spring Mail behind `ILearnerNotifier` (MailHog in dev).
- **Auth**: Spring Security; server-side session cookie via **Spring Session JDBC** (trainers and
  registered learners); opaque token for anonymous learners. No JWT.
- **Port naming**: `I{Context}{Type}` (house convention — yes, in Java).

## 3. Design decisions resolved during planning (→ write as ADR-0016…0020 in M0)

1. **CQRS-lite is Delivery-only** (→ ADR-0016). Authoring and Identity use aggregates + plain
   transactional reads off their own tables. No outbox, no projections outside Delivery.
2. **Grading-job enqueue rides the outbox** (→ ADR-0017). Enqueueing from the command handler is a
   dual write: crash after commit but before enqueue produces a Submission nobody ever grades, and
   ADR-0003's idempotency cannot repair a never-sent message. Instead, the relay enqueues to
   `IEvaluationWorkQueue` when draining a `SubmissionReceived` row, *before* marking it published.
   Crash-and-replay yields a duplicate enqueue, which ADR-0003 absorbs by design.
3. **Outbox ordering trap** (→ ADR-0017). A `bigserial` seq does not equal commit order: a
   transaction holding seq 5 can commit after seq 6 was already drained, and a forward-only cursor
   skips 5 forever. Fix: serialize outbox appends with `pg_advisory_xact_lock` inside the command
   transaction. Cost is nothing at classroom scale. Do not let anyone "optimise" this away.
4. **Broker-uniform abandonment and redrive** (→ ADR-0019). On the final delivery attempt (adapter
   sees `ApproximateReceiveCount` / `x-delivery-count` at the limit) the adapter reports the domain
   fact "grading abandoned"; the message dead-letters. Recovery is a domain-level
   `RetryAbandonedGradings` use case that re-enqueues — identical on both brokers, no AWS console
   required. Evaluation state machine: `undecided → proposed | abandoned | overridden`;
   `abandoned → proposed` is legal (redrive); `overridden` is terminal against LLM writes.
5. **Cross-context calls in the modular monolith** (→ ADR-0020): see §8.
6. **Web sessions & socket auth** (→ ADR-0018): Spring Session JDBC from day one (a session cookie
   valid on any web node is what makes web×N possible — ADR-0005 rejects single-replica designs);
   WebSocket handshakes authenticated by cookie (trainer / registered learner) or opaque token
   (anonymous learner); CSRF via cookie token for Angular.

## 4. Repository layout

```
keepup/
├── settings.gradle.kts
├── gradle/libs.versions.toml               # single version catalog
├── build-logic/                            # convention plugins: keepup.java, keepup.spring-adapter, keepup.archunit
├── backend/
│   ├── contexts/
│   │   ├── authoring/                      # feature pkgs: quizediting/, sharing/
│   │   ├── delivery/                       # sessionlifecycle/, answering/, grading/, triage/, course/, shared/
│   │   └── identity/                       # traineraccount/, learneraccount/
│   ├── platform/                           # outbox relay, LISTEN/NOTIFY plumbing, advisory-lock helpers.
│   │                                       #   Infrastructure only — zero domain knowledge.
│   └── app/                                # THE composition root: @SpringBootApplication, explicit @Bean
│                                           #   wiring per context (what /wire produces), security filter
│                                           #   chains, role gating, cross-context adapters + orchestrators.
├── frontend/                               # Angular workspace (npm-driven; own CI job)
├── infra/
│   ├── docker/                             # compose.dev.yml, compose.prod.yml
│   └── terraform/                          # SQS + DLQ + redrive + scoped IAM (eu-west-3) + short-visibility test queue
└── docs/                                   # CONTEXT-MAP.md, adr/, this plan
```

Rules the layout encodes:

- **Feature packages, not layer packages.** A feature folder holds its domain types, ports, use
  cases, adapters, and tests together. No global `ports/` or `usecases/` directories, ever.
- **Context modules never depend on each other.** Only `:backend:app` depends on all of them;
  cross-context adapters live there, making acyclicity a compile-time fact.
- **ArchUnit enforces the hexagon from M0** (adapters share a Gradle module with domain, so Gradle
  alone cannot): nothing outside `*.adapter.*` packages imports `org.springframework.*`,
  `jakarta.persistence.*`, or SDK types; domain and use-case packages have zero external deps;
  no cross-context imports; port naming `I{Context}{Type}` checked.
- **No component scanning of context modules.** Use cases and adapters are wired by explicit
  `@Bean` methods in `AuthoringConfig` / `DeliveryConfig` / `IdentityConfig` / `PlatformConfig`.
- Glossaries move next to their modules in M0 (`backend/contexts/X/CONTEXT.md`), per CONTEXT-MAP.

Delivery's internal feature packaging (reference for the other contexts):

```
backend/contexts/delivery/src/main/java/keepup/delivery/
├── sessionlifecycle/   # Session aggregate, JoinCode, Create/Start/End/ExpireSessions,
│                       #   ISessionRepository, IQuizSnapshotSource, IJoinCodeGenerator, JPA adapter
├── answering/          # Submission, OpenQuestion/CloseQuestion/SubmitAnswer, participation + anonymous token
├── grading/            # Evaluation state machine, Propose/Abandon/RetryAbandonedGradings,
│                       #   IEvaluationWorkQueue, ILlmGrader, RabbitMQ/SQS/OpenRouter adapters
├── triage/             # Override/Release/ReleaseAll/Discard, triage read model + queries,
│                       #   coverage denominators, identical-evidence anomaly flag
├── course/             # Course aggregate, grace rule, domain-restriction value, ClaimParticipation, radar
└── shared/             # Delivery-owned ids & event types (TrainerId, QuizId re-declared as opaque VOs;
                        #   no shared kernel across contexts — identifiers convert at the boundary)
```

## 5. Process topology

**One Spring Boot artifact, role-gated: `KEEPUP_ROLES=web|worker|relay`** (comma-separable), via a
custom `@OnRole` condition — not Spring profiles (profiles are for environments; roles are duties).

- Compose runs `web ×2, worker ×1, relay ×1` from one image with per-role heap
  (`web -Xmx384m`, `worker -Xmx256m`, `relay -Xmx160m`) — ~1.2–1.5 GB total, fits a 4 GB VPS
  beside Postgres and RabbitMQ. JVM *instances* cost memory, not jar size; separate boot modules
  would triple wiring surface for zero savings.
- Matches ADR-0008's aesthetic: `KEEPUP_QUEUE` flips the broker, `KEEPUP_ROLES` flips the duty.
- **Relay runs at exactly one replica**, guaranteed by a Postgres session-level advisory lock
  (a second relay starts, fails to acquire, idles and retries). Singleton scheduled jobs
  (session expiry, outbox pruning, Spring Session cleanup) live on the relay role.
- Web×N works because: Spring Session JDBC (cookie valid on any node), every web node LISTENs,
  and a dropped notification is repaired by browser reconnect + refetch (ADR-0005).

## 6. Working conventions (binding)

- Cadence per component: `/port` (define interface) → `/spec` (Given-When-Then tests) →
  `/usecase` (application service) → `/adapter` (infrastructure) → `/wire` (explicit @Bean in
  `:backend:app`). `/domain` precedes the first use case of a feature. UI: `/viewmodel` → `/view`.
- Given-When-Then structure; test business behavior, not implementation; assert on observable
  outcomes; mock **only injected driven ports**; one test file per component; spec before impl.
- Hexagonal + DDD for all code: dependencies point inward, domain has zero external dependencies,
  no external system type crosses a port boundary, adapters own all protocol logic.
- Validate each component (`/test`, `/review`) before `/commit`. One file per step where possible.

## 7. Milestones

Sequencing optimizes for: earliest full classroom demo (end of M4, RabbitMQ path, anonymous
learners) → SQS interchangeability deliverable (M5) → accounts/courses (M6) → sharing (M7) →
ops hardening (M8). Every milestone ends with a demo criterion exercised for real.

### M0 — Walking skeleton
**Demo: `docker compose up`; app boots in all three roles; CI green; ArchUnit already enforcing.**

- Gradle skeleton of §4, all modules compiling; version catalog; convention plugins.
- `:backend:app` boots with role gating + actuator health.
- `infra/docker/compose.dev.yml`: Postgres 15.8 (one schema per context + `platform` schema),
  RabbitMQ 4 with management UI. (MailHog joins in M6.)
  Production runs `supabase/postgres:15.8.x`; dev and Testcontainers match it exactly.
  See `docs/WORKFLOW.md` §1 for this and the other amendments of record.
- Flyway V1: schemas; outbox table (`seq bigserial`, payload, `published_at`) + projector cursor
  table; Spring Session tables (disable its auto-DDL).
- ArchUnit ruleset live and failing on violations.
- Angular workspace + dev proxy. Playwright harness stub.
- CI (GitHub Actions): backend job (Gradle build + Testcontainers), frontend job (lint/test/build),
  secrets-gated `sqs-contract` job (manual / main-only).
- Move glossaries next to modules; leave pointers in `docs/contexts/`.
- **Write ADR-0016…0023** (done — slice S0.7): 0016 only Delivery pays for CQRS · 0017 the relay
  enqueues the grading job, and the outbox is appended under a lock · 0018 the web session lives in
  Postgres, and the cookie authenticates the socket · 0019 abandonment is a domain fact, and redrive
  is a use case · 0020 no context imports another, so the crossing lives in the composition root ·
  0021 keepup connects to Postgres directly, and never through the pooler · 0022 Gradle serves the
  contract suite, and JPA serves three aggregates and nothing else · 0023 OpenRouter is an adapter,
  and the port is where the rules live.
  (Process topology & relay duties gets no ADR: web×N is settled by 0018 and the relay's singleton
  lock by 0021; what remains is deployment configuration, documented in §5.)

### M1 — Trainer identity + Authoring core
**Demo: a provisioned trainer logs in and authors a quiz with questions and criteria in Angular.**

Build order:
1. `identity/traineraccount`: `/domain` TrainerAccount (TrainerId, Username, PasswordHash), Username VO
2. `/port` `ITrainerAccountRepository`, `IPasswordHasher` → `/spec` → `/usecase` ProvisionTrainer
   (operator CLI runner/seed — no signup surface, ADR-0013), AuthenticateTrainer →
   `/adapter` JPA account adapter + BCrypt (spring-security-crypto) → `/wire`
3. `/wire` security: JSON/form login → session cookie, Spring Session JDBC, CSRF cookie for Angular
4. `authoring/quizediting`: `/domain` Quiz aggregate (ordered Questions, Criteria per Question;
   invariants: non-empty text, ≥1 criterion per question)
5. `/port` `IQuizRepository` → `/spec` → `/usecase` CreateQuiz, RenameQuiz, AddQuestion,
   EditQuestion, RemoveQuestion, DeleteQuiz; JdbcClient queries ListCollection, GetQuiz
   (plain reads — no CQRS here, §3.1)
6. `/adapter` JPA quiz adapter (the one place cascades pay) + REST controllers → `/wire`
7. Frontend: login, collection list, quiz editor (`/viewmodel` + `/view` each)

### M2 — Delivery write path: session, snapshot, join, answer
**Demo: session started from a real quiz; learner joins by code on a phone and submits; an
undecided Evaluation row exists; the grading job is visible in the RabbitMQ management UI.**

1. `sessionlifecycle`: `/domain` Session (created → started → ended | expired), JoinCode VO
   (minted at creation, admits nobody until start), frozen SessionQuestion + SessionCriterion
   (copies — ADR-0001), Participant (anonymous: token hash + declared first name)
2. `/port` `ISessionRepository`, `IQuizSnapshotSource` (§8), `IJoinCodeGenerator` → `/spec` →
   `/usecase` CreateSession, StartSession (fetch snapshot, freeze, emit SessionStarted),
   JoinSession → `/adapter` JPA session adapter (snapshot adapter lives in `:backend:app`) → `/wire`
3. Outbox: `/port` `IDeliveryOutbox` → `/adapter` JdbcClient writer (same transaction,
   `pg_advisory_xact_lock` serialization — §3.3) → `/wire`
4. `answering`: `/domain` Submission (final on send; unique per participant + question) →
   `/usecase` OpenQuestion, SubmitAnswer (writes Submission + undecided Evaluation +
   `SubmissionReceived` outbox row in ONE transaction) →
   `/adapter` JdbcClient writer with `ON CONFLICT DO NOTHING` → `/wire`
5. `/port` `IEvaluationWorkQueue` (enqueue half) → `/adapter` RabbitMQ enqueue → `/wire`
6. `platform`: relay v1 — drain in seq order: enqueue grading jobs for SubmissionReceived →
   project minimal session/participant read model → mark published. `/spec` heavily:
   replay after crash, crash mid-batch, duplicate enqueue tolerated.
7. Frontend: join screen, learner question list + answer editor, trainer dashboard skeleton

### M3 — Grading pipeline
**Demo: learner submits → verdicts with evidence appear live on the trainer's triage screen;
revoke the OpenRouter key → Evaluations surface as abandoned; a retry action regrades them.**

1. `grading`: `/domain` Evaluation state machine (`undecided → proposed | abandoned | overridden`;
   `abandoned → proposed` legal; `overridden` terminal vs LLM writes — §3.4); Verdict + Evidence VOs
   (met ⇒ verbatim evidence; not-met ⇒ none — ADR-0007)
2. `/port` `ILlmGrader` (frozen criteria + submission text in; domain ProposedGrading out;
   no provider type crosses)
3. `/spec` → `/usecase` ProposeEvaluation (idempotent: act only if undecided/abandoned;
   best-effort existence check before the LLM call; unique-constraint backstop),
   AbandonGrading, RetryAbandonedGradings
4. `/adapter` RabbitMQ consume side: quorum queue + `delivery-limit` + DLX; `x-delivery-count`
   at limit → AbandonGrading (a domain fact — the domain never sees a receive count); prefetch=1
5. **Contract suite skeleton now** (ADR-0008): abstract `EvaluationWorkQueueContract` in the
   delivery module's `testFixtures` + RabbitMQ Testcontainers subclass. Writing it alongside the
   first adapter keeps the contract honest. Tests: delivery; redelivery after timeout; duplicate
   and out-of-order tolerance; attempt exhaustion produces exactly one "grading abandoned" fact.
6. `/adapter` OpenRouterLlmGrader: criteria in system prompt; submission in a delimited,
   explicitly-untrusted user turn; forced structured tool call (`tool_choice` pinned to the
   function, `provider.require_parameters=true`); mechanical validation — verbatim evidence after
   whitespace/case normalization, exactly one verdict per criterion, criterion ids match the frozen
   copy; one retry then abandon (ADR-0007/0011); WireMock integration tests
7. Projector v2: triage read model — one row per Evaluation (first name, per-criterion verdicts,
   evidence, state), **coverage denominators** (`27/30 answered` — ADR-0012), **identical-evidence
   anomaly flag** computed at projection time (ADR-0011)
8. `/port` `ISessionNotifier` → `/adapter` Postgres NOTIFY on the relay (project → notify → mark,
   id-only payload — ADR-0005/0006); web-side listener: dedicated non-pooled `PgConnection`,
   500 ms `getNotifications` poll, reconnect with backoff + "resync" push; WebSocket push to
   Angular (cookie-authenticated handshake) → `/wire`
9. Frontend: live triage screen with reconnect-refetch behavior

### M4 — Decision loop: the full classroom demo
**Demo: a complete class run over RabbitMQ, end to end, with web ×2 — kill one web node
mid-session and reconnect repairs.**

1. `triage`: `/spec` → `/usecase` OverrideEvaluation (any state; trainer supplies verdicts),
   ReleaseEvaluation (graded-only, repeatable — ADR-0004), ReleaseAllCurrentlyGraded (the bulk
   action that keeps triage viable — ADR-0012), DiscardQuestionEvaluations
2. `answering`: `/usecase` CloseQuestion — ends answering AND reveals Criteria to **all** session
   participants, answered or not (glossary's Close entry is canonical)
3. `sessionlifecycle`: `/usecase` EndSession (blocked while any graded Evaluation is neither
   released nor discarded — ADR-0010; in-flight grading completes after end),
   ExpireSessions (24 h scheduled job, relay role)
4. Learner read model + screens: **two rendering states per Evaluation** (before Close: own
   verdicts + own evidence only; after: criteria revealed); learner WebSocket
   (token-authenticated handshake)
5. Trainer command HTTP responses carry the new state (ADR-0006's lag mitigation) —
   enforced by controller contract tests
6. Frontend: release/override/discard actions; close-question flow with a "you are cutting off
   these specific people" affordance (ADR-0012); end-of-session forced-decision modal (ADR-0010);
   learner feedback view

### M5 — SQS adapter + Terraform: the interchangeability deliverable
**Demo: ONE contract suite green twice — Testcontainers RabbitMQ and real eu-west-3 SQS;
`KEEPUP_QUEUE` flipped on the VPS while a session is running.**

1. Terraform: main queue + DLQ + redrive (`maxReceiveCount`) + IAM user scoped to the queue ARNs,
   eu-west-3; **plus a short-visibility test queue pair** (visibility 2 s, maxReceiveCount 2) so
   give-up tests finish in seconds
2. `/adapter` SqsEvaluationWorkQueue: 20 s long-poll; visibility timeout 120 s (≫ the 8 s+ LLM
   worst case); `ApproximateReceiveCount` at limit → AbandonGrading; delete on success; NO delete
   on final failure so the message dead-letters and stays redrivable
3. Contract suite: SQS subclass, `@EnabledIfEnvironmentVariable`-gated on credentials + queue URL;
   correlation-id message filtering, never `PurgeQueue` (60 s throttle)
4. `/wire` `KEEPUP_QUEUE` conditional wiring; gated CI job runs the SQS leg

### M6 — Learner accounts, courses, registration, claim (ADR-0015)
**Demo: the week-2 flow — anonymous first session; register in the same sitting; claim; join
session 2 with the account; feedback survives a closed tab; trainer sees the longitudinal radar.**

1. `identity/learneraccount`: `/domain` LearnerAccount, EmailAddress VO, VerificationToken →
   `/port` `ILearnerAccountRepository`, `ILearnerNotifier` → `/spec` → `/usecase` RegisterLearner
   (optional email-domain restriction passed **as a value parameter** — Identity never reads a
   Course), VerifyEmail, AuthenticateLearner, RequestPasswordReset/ResetPassword →
   `/adapter` Spring Mail SMTP (MailHog in compose) → `/wire`
2. `delivery/course`: `/domain` Course (named Session sequence, one Trainer, optional email-domain
   restriction) → `/usecase` CreateCourse, CreateSessionInCourse, the one-Session-grace guard in
   JoinSession (second Course session requires LearnerAccountId; standalone sessions never do),
   ClaimParticipation (binds the token's participation rows to the account — only while the
   token lives)
3. `:backend:app` registration orchestrator: Delivery restriction query → Identity RegisterLearner
   → on email verification, Delivery ClaimParticipation (identifiers only — §8)
4. Registered-learner login (same session machinery); account feedback history view (released
   feedback belongs to the account — repairs ADR-0004's redrive-after-dispersal story)
5. Course radar read model (trainer-only) + projector extension
6. Frontend: in-session registration prompt (fired after answering, same sitting), course screens, radar

### M7 — Sharing & import (ADR-0014)
**Demo: two trainers; share, browse public quizzes with owner Username, import a full editable
copy, un-share leaves the copy untouched.**

1. `authoring/sharing`: `/domain` public flag + lineage id on Quiz → `/spec` → `/usecase`
   ShareQuiz, UnshareQuiz, ImportQuiz (full copy of questions + criteria, importer-owned),
   BrowsePublicQuizzes
2. `/port` `ITrainerDirectory` (Username by TrainerId) → `/adapter` in `:backend:app` over
   Identity's query service → `/wire`
3. Frontend: public gallery, import action, lineage display

### M8 — Ops hardening
Outbox pruning (published rows older than N days); Spring Session cleanup; prod compose
(Caddy/nginx with WebSocket upgrade, web ×2); Postgres backups; AWS key rotation note; login rate
limiting (adapter concern — ADR-0013); the ADR-0015 deletion-story debt ticketed, not built.

## 8. Cross-context integration pattern (ADR-0020)

**Driven port in the consuming context, returning context-owned value objects; the adapter lives
in `:backend:app`** (the only module that sees both contexts) and calls the sibling context's
public query/use case in-process; field-by-field mapping IS the copy. No entity crosses; ArchUnit
proves no context imports another. Rejected: direct SQL into a sibling's schema (couples to a
schema the consumer doesn't own); event-carried state transfer (machinery an in-process call
doesn't need).

The three crossings:
- `IQuizSnapshotSource` (Delivery ← Authoring): `QuizSnapshot fetch(QuizId, TrainerId requester)`
  returns a Delivery-owned VO (ordered question texts + criterion texts + quizId for lineage).
  Authoring side: `GetQuizForRun(quizId, trainerId)` enforcing Collection ownership.
- `ITrainerDirectory` (Authoring ← Identity): Username for public-quiz attribution.
- Registration orchestration (Delivery ↔ Identity, M6): sequenced in `:backend:app`,
  identifiers and one copied domain-restriction value only.

## 9. Testing strategy

- **Domain specs**: plain JUnit 5, zero Spring, Given-When-Then names — Evaluation state machine,
  Session lifecycle guards, verbatim-evidence rule, join-code admission, end-session blocking.
- **Use-case specs**: JUnit + Mockito; mock **only injected driven ports**. Canonical example:
  *given an overridden Evaluation, when a duplicate delivery arrives, then ILlmGrader is never
  called and the message is acknowledged.*
- **Adapter integration**: Testcontainers Postgres (JPA adapters, outbox writer, projector —
  replay same seq twice is a no-op, crash-mid-batch resume, LISTEN/NOTIFY round-trip);
  Testcontainers RabbitMQ; WireMock for OpenRouter (malformed tool call → one retry → abandon;
  paraphrased evidence → rejected).
- **ADR-0008 contract suite**: one abstract JUnit class in delivery `testFixtures`
  (`EvaluationWorkQueueContract`) with factory hooks; RabbitMQ subclass runs every CI build;
  SQS subclass runs against the real Terraform-provisioned test queue, env-gated.
- **ArchUnit**: continuous from M0.
- **E2E smoke** (from M4): Playwright over `docker compose up` with WireMocked OpenRouter (real
  adapter code runs): login → author → start → join → submit → triage shows verdicts → release →
  learner sees feedback → close reveals criteria. One path, under two minutes.

## 10. Risk register

| # | Risk | Mitigation |
|---|------|------------|
| 1 | Hikari connections cannot LISTEN (reset on return; notifications silently lost) | Dedicated raw non-pooled `PgConnection` in a polling loop (500 ms), reconnect with backoff, generic "resync" push on reconnect (clients refetch) |
| 2 | JPA/Spring types leaking into domain | Separate persistence entities + hand mapping (no MapStruct), `ddl-auto=validate`, ArchUnit tripwire; `flush()` before writing outbox rows that use generated ids |
| 3 | Visibility timeout vs 8 s+ LLM calls → double grading | 120 s visibility ≫ worst case; race resolved by unique-constraint catch → ack → discard; `overridden` never overwritten by LLM writes |
| 4 | Relay ordering/singleness | Session advisory lock (singleness), xact advisory lock on append (order = commit order), strictly ascending cursor; spec every crash window |
| 5 | OpenRouter tool-call variance (prose alongside call, malformed args) | Pin one known-good tool-calling model; force `tool_choice`; `provider.require_parameters=true`; strict schema validation; ignore text content; retry once → abandon |
| 6 | Missing Spring Session JDBC silently breaks login at web×2 | In from M0, non-negotiable |
| 7 | Evidence is attacker-controlled text in the trainer's browser (ADR-0011) | Angular interpolation only; no `innerHTML` ever; ESLint rule |
| 8 | Flyway ↔ JPA drift | `validate` mode from M0: drift fails at boot, not mid-class |
| 9 | Never batch submissions into one LLM call (ADR-0011: injection → exfiltration vector) | One submission per call is a hard rule; contract-tested in the OpenRouter adapter |

## 11. Verification gates

- Per component: spec suite green before moving on (`/test`); `/review` before `/commit`.
- Per milestone: its demo criterion executed for real (listed under each milestone).
- M4 gate: full class run on compose with web ×2; kill one web node mid-session; reconnect repairs.
- M5 gate: contract suite green on both brokers; live `KEEPUP_QUEUE` flip during a running session.
- Continuous: ArchUnit + E2E smoke in CI.

## 12. First actions for the implementing session

1. ~~Write ADR-0016…0023 (contents in §2, §3, §5, §8, and `docs/WORKFLOW.md` §1.1).~~ **Done** —
   slice S0.7. The three points left open in them have since been decided by the product owner and
   are recorded in the ADRs themselves: the mid-registration Claim is retried while the browser token
   lives and no durable claim-intent is built (ADR-0020); the pooler is forbidden in *any* mode,
   session mode included (ADR-0021); `RetryAbandonedGradings` is Trainer-triggered only, with no
   automatic sweep (ADR-0019).
2. Execute M0 in order: Gradle skeleton → compose → Flyway V1 → ArchUnit → Angular workspace →
   CI → glossary relocation.
3. Begin M1 with `/domain` TrainerAccount.
