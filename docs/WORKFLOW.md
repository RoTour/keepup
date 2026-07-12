# keepup — Delivery Workflow

> Written 2026-07-12. Companion to `docs/IMPLEMENTATION-PLAN.md`: the plan says **what** to build,
> this says **how the work moves** — how it is cut into parallel slices, how agents execute it with
> minimum context, how it reaches staging and production.
>
> Precedence: **ADRs > IMPLEMENTATION-PLAN > this document.** Where this document contradicts the
> plan, §1 says so explicitly and gives the reason; those are deliberate amendments, not drift.

---

## 1. Amendments to `IMPLEMENTATION-PLAN.md`

Established from the live VPS on 2026-07-12 and decided by the product owner the same day.
**This document is the amendment of record.**

**1.1 — Never connect through Supavisor.** The VPS runs a Supabase stack whose Postgres is fronted
by Supavisor. ADR-0005/0006 require `LISTEN/NOTIFY`; plan §5 requires a *session-level* advisory lock
to hold the relay at exactly one replica. **Neither survives a transaction-mode pooler**: a pooled
connection is handed to another transaction between statements, so the listener loses its channel
silently, and a session lock is released the instant its transaction ends. The failure mode is not an
error — it is *nothing happening*, discovered mid-class.

Host port `5432` maps straight to the `supabase-db` container, so the direct path exists. Bind it as
a rule: **keepup's `DATABASE_URL` always targets the Postgres container directly (5432, session
mode). Supavisor (6543 / transaction mode) is forbidden, for every role.** → ADR-0021.

**1.2 — Postgres is 15.8 everywhere.** Production is `supabase/postgres:15.8.1.085`. The plan's M0
said Postgres 17; that is wrong. Dev compose and Testcontainers both use `postgres:15.8-alpine`.
Production's image is stock PG 15.8 plus Supabase extensions we do not use. If we ever adopt a
Supabase-only extension, the dev image switches to the Supabase one.

**1.3 — RabbitMQ is the only deployed broker.** Nothing is provisioned on the VPS today; a RabbitMQ 4
container is an M0 deliverable (S0.10), with vhosts `staging` and `prod`. **Staging and production
run the same broker** — a staging that exercises a different broker than production does not derisk
production, and the first real test of the prod queue path must not be a live class.

**1.4 — The SQS adapter is still built, just not deployed.** ADR-0008 says both adapters are
production paths, and that stays true: the SQS enqueue adapter is written beside RabbitMQ's in M2,
the consume adapter beside RabbitMQ's in M3, and the ONE contract suite runs against **a real
eu-west-3 SQS queue** in CI. Terraform therefore stays at M0 (S0.6) — it is off the critical path,
fully parallel, and the contract suite needs a real queue by M3.

What SQS does *not* get is a running deployment. M5 is no longer "build the SQS adapter"; it is only
"prove interchangeability": the `KEEPUP_QUEUE` conditional wiring, the contract suite green on both
legs, and one live flip during a running session.

**1.5 — Feature branches are cut from `staging`, not `master`.** See §3. This replaces the model
sketched in the original brief and removes its central hazard.

---

## 2. Environments

| | local | staging | production |
|---|---|---|---|
| Runs on | M4 Mac, arm64 | Coolify / VPS, amd64 | Coolify / VPS, amd64 |
| Postgres | `postgres:15.8-alpine` in compose | db `keepup_staging` | db `keepup_prod` |
| | | *same PG 15.8 instance, separate databases, separate roles* | |
| Broker | RabbitMQ 4 in compose | RabbitMQ, vhost `staging` | RabbitMQ, vhost `prod` |
| `KEEPUP_QUEUE` | `rabbit` | `rabbit` | `rabbit` |
| SQS | — | *(CI contract suite only)* | *(CI contract suite only)* |
| LLM | WireMock | WireMock *or* live OpenRouter, own key | live OpenRouter, own key |
| Mail | MailHog | MailHog | SMTP provider |
| Image | built locally, arm64 | `ghcr.io/rotour/keepup-*:<sha>` amd64 | the **same digest**, promoted |

VPS capacity is 16 GB RAM / 100 GB disk — ample for staging *and* production side by side
(~1.2–1.5 GB each per plan §5, plus ~250 MB RabbitMQ) alongside everything already on the box.

Two rules make "staging is production with different env vars" true rather than aspirational:

- **Staging and production are the same image digest.** Production is never rebuilt. Promotion
  re-tags the digest staging already validated. A rebuild is a different artifact, and a different
  artifact is an unvalidated one.
- **Separate databases, not separate schemas.** The plan's schema-per-context layout (`authoring`,
  `delivery`, `identity`, `platform`) must be byte-identical in both, so the environment boundary has
  to sit above it. Each database has one owning role with rights to nothing else.

**Migrations run once, from a one-shot `migrate` service**, not at boot from `web ×2 + worker +
relay` racing each other for Flyway's lock. Everything else `depends_on: { migrate: { condition:
service_completed_successfully } }`, and the app roles boot with `spring.flyway.enabled=false` and
JPA `ddl-auto=validate` — so a missed migration fails the container at startup, loudly, rather than
at 09:05 in front of a class.

---

## 3. Branch and promotion model

```
feat/<slice-id>-<title>   ──PR──►  staging  ──promote (fast-forward)──►  master
        ▲                             │
        └────── branched from ────────┘
```

- **`master` is production.** It only ever moves by fast-forward from a validated `staging`.
- **`staging` is pre-production and the integration branch.** Isomorphic to production (§2).
- **`feat/*` branches from `staging`** and merges back into `staging` by PR after `/review-pro`.

Cutting from `staging` rather than `master` is what makes this build tractable. The work is
dependency-dense — S1.4 needs S1.3's aggregate, S2.7 needs S2.3's outbox — and a branch cut from
`master` cannot see anything merged to `staging` but not yet promoted. That is not a corner case;
it is most slices. Branching from `staging` means a slice sees its dependencies the moment they
merge, and `master` promotion becomes a purely independent cadence.

The price is that a slice may build on work that has not yet reached production. Two rules pay it:

**Rule A — A red slice leaves `staging` immediately.** If a slice fails validation *on* staging,
revert it out rather than letting it block the promotion of everything queued behind it. Because
other branches now build on `staging`, a revert is more disruptive than before — which is exactly why
it must be fast. Never debug a broken slice *in* staging.

**Rule B — Stack only within a wave.** If your slice depends on a sibling that has not merged yet,
branch from **that sibling's branch** and open the PR with an explicit base, so the diff under review
is only your own work:

```bash
git switch -c feat/S1.4-quiz-commands feat/S1.3-quiz-aggregate
gh pr create --base feat/S1.3-quiz-aggregate --draft   # not --base staging
```

When the parent merges to `staging`, retarget the child (`gh pr edit --base staging`) and rebase. The
slice inventory (§6) marks every stacked slice's base, so this is decided up front rather than
discovered.

**Rule C — Promote on the demo criterion.** `master` fast-forwards from `staging` whenever staging is
green and a coherent unit of work is complete — at minimum, every milestone's demo criterion (plan
§7). More often is fine; never let it lag by more than a milestone.

### 3.1 PR discipline

- Every PR is reviewed with **`/review-pro`** before it is marked ready. Findings are fixed on the
  same branch.
- **Agents commit and push their branch. They do not open PRs and they do not merge.** Opening a PR
  on a public repo is outward-facing, and a merge is not reversible the way a local commit is. A
  human opens the draft PR, runs the review, marks it ready, and merges.
- One slice = one PR = one squash-merge commit on `staging`.
- Merge in **DAG order** (§6). Out-of-order merges create exactly the conflicts §5 exists to avoid.

### 3.2 Branch protection (S0.10)

- `master`: no direct pushes; fast-forward-only from `staging`; required checks green.
- `staging`: no direct pushes; PR required; squash-merge only (linear history); required checks
  `backend-test`, `frontend-test`, `raw-html-gate`, `secrets-scan`.

**The path-filter trap — decide this when configuring the required checks.** `backend-test`,
`frontend-test` and `raw-html-gate` are `paths:`-filtered (they only run when their area changes).
A GitHub *required* check that never triggers is stuck as "Expected — waiting" and blocks the PR
**forever** — so a docs-only PR (an ADR, a plan edit) would never merge. `secrets-scan` is not
path-filtered and is always safe to require directly. Two ways to make the other three safe to
require:
- **Preferred (do at S0.10 or first idle moment): one aggregate check.** Consolidate the four PR
  gates into a single `pr-checks.yml` where each job self-filters (`dorny/paths-filter`) and a final
  `all-checks-passed` job `needs:` them with `if: always()`, failing on any `failure`/`cancelled`,
  passing on `skipped`. Require only `all-checks-passed`. One stable check name, "not applicable =
  pass" semantics, and adding gates in later milestones never touches branch-protection config again.
- **Zero-restructure fallback:** drop the workflow-level `paths:` filters from the three gates, so
  they always run and always report. Costs one `gradlew build` / `npm ci` per docs-only PR.

Do **not** mark a path-filtered check as required while its filter remains — that is the exact
configuration that hangs PRs.

---

## 4. The parallel agent model

The goal is that **N agents work simultaneously and none of them needs to understand the project.**
Those are the same goal. An agent that must read `IMPLEMENTATION-PLAN.md`, the CONTEXT-MAP, and five
ADRs to discover what a `Verdict` is has burned 30k tokens before writing a line — and it is *also*
an agent that now has opinions about files it does not own.

### 4.1 The mechanism: contract-first, then fan out

Each milestone opens with a **contract slice** (`S<n>.0`), authored by the orchestrating session, not
by an agent. It contains nothing but signatures:

- the port interfaces that milestone introduces (`I{Context}{Type}`, full method signatures);
- the HTTP surface (endpoints + request/response DTO shapes);
- the domain types crossing between slices.

Once it exists: backend slices code **against the port**, not against each other; frontend slices code
**against the DTOs** without waiting for any backend slice to land; and every agent's brief can be
made self-contained by *inlining the relevant fragment* rather than pointing at it.

This is the hexagon paying rent. The ports were always going to be the seams of the code; the
contract slice makes them the seams of the *schedule* too.

### 4.2 The within-slice DAG

The house cadence looks sequential. It is not — after the port exists, it forks:

```
/domain ──► /port ──┬──► /spec (use case) ──► /usecase ────┐
                    │                                       ├──► /wire ──► /test ──► /review-pro
                    └──► /adapter (+ its integration test) ─┘
```

The **use case consumes the port; the adapter implements it.** They share nothing but the interface
and do not meet until `/wire`. That is two agents for most slices, and neither needs to know the
other exists.

`/spec` before `/usecase` stays strictly sequential: the spec is the contract for the implementation,
so the same agent writes it, watches it fail, then makes it pass.

### 4.3 The work packet

An agent's entire context is one packet, generated into the scratchpad. Packets are ephemeral — the
*inventory* (§6) is what persists and lets a fresh session regenerate them.

```markdown
# Packet <slice-id>/<lane> — <title>
Branch:   feat/<slice-id>-<title>
Base:     staging | feat/<parent-slice>
Worktree: ../keepup-wt/<slice-id>
Skill:    /domain | /port | /spec | /usecase | /adapter | /wire

## Files you own — create or modify ONLY these
<explicit list>

## Contract — verbatim, do not go looking for it
<the port interface / DTO / type signature, pasted in full>

## Rules that bind this packet
<the two or three ADR sentences that actually constrain this code, pasted in full —
 not "see ADR-0007">

## Glossary terms you will use
<the three or four entries, pasted in full>

## Done when
- [ ] <the exact gradle/npm command> green
- [ ] ArchUnit green
- [ ] Given-When-Then test names; one test file per component; mocks only on injected driven ports

## Out of scope — hard boundaries
- Do NOT read docs/IMPLEMENTATION-PLAN.md, CONTEXT-MAP.md, or any ADR file.
  Everything you need is above. If it genuinely is not, stop and say so.
- Do NOT touch: <files owned by sibling slices in this wave>
- Do NOT open a PR, do NOT merge, do NOT push to staging or master.
```

The "do not read the plan" line is the load-bearing one: it makes the packet a *budget* rather than a
suggestion. If an agent reports its packet is insufficient, that is a defect in the packet — fix the
packet, do not lift the boundary.

Typical packet: under 2k tokens. Typical agent context: the packet plus the files it owns. **The
orchestrator holds the plan; the agents hold packets.**

### 4.4 Isolation

Every agent runs in its own git worktree, so parallel agents cannot see or clobber each other's
working tree.

### 4.5 The orchestrator's loop, per wave

1. Cut the wave's packets from the slice inventory and the milestone contract.
2. Spawn the wave's agents **in one message**, in worktrees. Never more than the contention map (§5)
   allows.
3. As each returns: push its branch, open a draft PR, `/review-pro`, fix findings, mark ready.
4. Merge to `staging` in DAG order.
5. Next wave. Promote `master` per Rule C.

---

## 5. Contention map — the files that serialise everything

Parallel agents fail on shared files, not on shared ideas. Six files want to be edited by every
slice; each needs a protocol, and the protocols are what make §4 work at all.

| Hot file | Protocol |
|---|---|
| **Flyway migrations** | **Timestamped versions, never sequential integers.** `V20260712_1430__add_session_tables.sql`. Two parallel branches both claiming `V2__` is not a merge conflict — it is a *silent* one: whichever lands second either fails a checksum or is skipped, and you find out when a table is missing. Timestamps cannot collide across branches. Non-negotiable. |
| **`:backend:app` composition root** | **One `@Configuration` class per feature package**, not per context: `wiring/delivery/GradingConfig.java`, `wiring/delivery/TriageConfig.java`, … Each slice owns its own file, so `/wire` produces zero conflicts. A parent `@Import({…})` list collects them; that list takes a one-line append per slice — a trivial conflict, resolved by taking both sides. |
| **`gradle/libs.versions.toml`** | Append-only, sections alphabetical. Conflicts are one-line adds; take both sides. |
| **`settings.gradle.kts`** | **Frozen after M0.** S0.1 declares every module — including empty ones — precisely so nothing after M0 touches this file. |
| **Angular routes / providers** | Same shape as the composition root: one feature-routes file per slice, collected by a parent. |
| **`.github/workflows/`** | Owned by S0.5. CI changes are their own slice, never a passenger in a feature PR. |

**M0 is the anti-parallel milestone, and that is the point.** It exists to create every module, every
empty feature package, every config stub, and the ArchUnit ruleset — so that M1 through M8 can run six
agents wide without any of them touching a shared file. Over-provision the skeleton: every stub S0.1
creates is a merge conflict that never happens.

---

## 6. Slice inventory

A **slice** is one `feat/*` branch, one PR, one `/review-pro` — sized to be coherent and demoable,
roughly one numbered sub-item of a milestone. `∥` marks slices safe to run concurrently.

### Pinned toolchain (S0.1 establishes; nothing else changes it)

Java **21** (Gradle toolchain auto-provisioned via the foojay resolver — the local JDK is 19 and that
is fine), Gradle **9.6.1**, Spring Boot **4.1.0**, Angular **22**, Postgres **15.8**, RabbitMQ **4**.

### M0 — Walking skeleton

| Slice | What | Base | Wave |
|---|---|---|---|
| S0.1 | Gradle skeleton: `settings.gradle.kts` (**all** modules + **all** empty feature packages), `build-logic/` convention plugins (`keepup.java`, `keepup.spring-adapter`, `keepup.archunit`), version catalog, **ArchUnit ruleset live and failing on violations** | staging | **A** ∥ |
| S0.2 | `infra/docker/compose.dev.yml`: Postgres **15.8**, RabbitMQ 4 + management, MailHog. *Backing services only* — the `app` and `migrate` services are added by S0.9, which owns the Dockerfiles they reference | staging | **A** ∥ |
| S0.4 | Angular 22 workspace + dev proxy + Playwright harness stub | staging | **A** ∥ |
| S0.6 | Terraform: SQS main + DLQ + redrive, short-visibility test pair, scoped IAM, **S3 state backend** (eu-west-3) | staging | **A** ∥ |
| S0.7 | ADR-0016…0021 (plan §3/§5/§8, plus **ADR-0021: direct Postgres, never the pooler** — §1.1) | staging | **A** ∥ |
| S0.5 | CI: `backend-test`, `frontend-test`, `secrets-scan`, `raw-html-gate`, `build-push`, `sqs-contract`, `deploy` (§8). References the Dockerfiles S0.9 creates at the pinned paths (`infra/docker/Dockerfile.{backend,frontend}`) — no file overlap, a build-arg contract | staging | **B** ∥ |
| S0.8 | Glossaries move to `backend/contexts/*/CONTEXT.md`; pointers left in `docs/contexts/` | staging | **B** ∥ |
| S0.9 | `:backend:app` boots: `@OnRole` condition, role gating, actuator health; a `@SpringBootTest contextLoads` smoke test (deferred from S0.1, which steers around the JUnit 6 / Boot 4.1 TestEngine wiring); backend + frontend Dockerfiles at `infra/docker/Dockerfile.{backend,frontend}` (§7); adds the `app` service to S0.2's compose. **Not** the `migrate` service — that runs Flyway and belongs to S0.3 | staging | **B** ∥ |
| S0.3 | Flyway V1: per-context schemas, outbox (`seq bigserial`, payload, `published_at`), projector cursor, Spring Session tables (auto-DDL off); the one-shot `migrate` compose service + wiring `app` to `depends_on: migrate`. **Stacked on S0.9** — both touch the app module's config and the `app` compose service, so sequencing them avoids a shared-file conflict rather than racing it | feat/S0.9 | **B (after S0.9)** |
| S0.10 | **Human-run.** Coolify: staging + prod apps, RabbitMQ container (vhosts `staging`/`prod`), two databases + roles, env vars, deploy webhooks; GitHub branch protection (§3.2) | — | **C** |

Concurrency: 5 agents, then 4. **Demo:** `docker compose up`; boots in all three roles; CI green;
ArchUnit already rejecting violations.

### M1 — Trainer identity + Authoring core

| Slice | What | Base | Wave |
|---|---|---|---|
| S1.0 | **Contract** (orchestrator): `ITrainerAccountRepository`, `IPasswordHasher`, `IQuizRepository`; auth + quiz HTTP/DTO surface | staging | — |
| S1.1 | Trainer identity: `TrainerAccount` + `Username`/`PasswordHash` VOs, both ports, specs, `ProvisionTrainer` + `AuthenticateTrainer`, JPA adapter, BCrypt adapter, wire | staging | **A** ∥ |
| S1.3 | Quiz aggregate: `Quiz`/`Question`/`Criterion`, invariants (non-empty text, ≥1 criterion per question), `IQuizRepository`, domain specs | staging | **A** ∥ |
| S1.6 | FE: login viewmodel + view *(against S1.0's DTOs — does not wait for S1.2)* | staging | **A** ∥ |
| S1.7 | FE: collection list + quiz editor *(against S1.0's DTOs)* | staging | **A** ∥ |
| S1.2 | Trainer auth wiring: Spring Security chain, JSON login → session cookie, **Spring Session JDBC**, CSRF cookie for Angular; operator provisioning CLI runner (ADR-0013: no signup surface) | feat/S1.1 | **B** |
| S1.4 | Quiz commands: `CreateQuiz`, `RenameQuiz`, `AddQuestion`, `EditQuestion`, `RemoveQuestion`, `DeleteQuiz` + specs | feat/S1.3 | **B** ∥ |
| S1.5 | Quiz persistence + REST: JPA quiz adapter, JdbcClient reads (`ListCollection`, `GetQuiz`), controllers, wire | feat/S1.3 | **B** ∥ |

S1.4 ∥ S1.5 is §4.2 in action: one consumes `IQuizRepository`, the other implements it.
Concurrency: 4, then 3. **Demo:** provisioned trainer logs in, authors a quiz in Angular.

### M2 — Delivery write path

| Slice | What | Base | Wave |
|---|---|---|---|
| S2.0 | **Contract**: `ISessionRepository`, `IQuizSnapshotSource`, `IJoinCodeGenerator`, `IDeliveryOutbox`, `IEvaluationWorkQueue` (enqueue half); session/answering HTTP surface | staging | — |
| S2.1 | `sessionlifecycle`: `Session` (created→started→ended\|expired), `JoinCode` VO, frozen `SessionQuestion`/`SessionCriterion` (ADR-0001), `Participant`; `CreateSession`/`StartSession`/`JoinSession`; JPA adapter | staging | **A** ∥ |
| S2.3 | Outbox: `IDeliveryOutbox` + JdbcClient writer, **`pg_advisory_xact_lock` on append** (plan §3.3 — serialises seq with commit order; do not let anyone optimise it away) | staging | **A** ∥ |
| S2.5 | RabbitMQ enqueue adapter | staging | **A** ∥ |
| S2.6 | SQS enqueue adapter (§1.4 — built, not deployed) | staging | **A** ∥ |
| S2.8 | FE: join screen, learner question list, answer editor | staging | **A** ∥ |
| S2.9 | FE: trainer dashboard skeleton | staging | **A** ∥ |
| S2.2 | Quiz-snapshot crossing (ADR-0020): `GetQuizForRun` in authoring + `IQuizSnapshotSource` adapter in `:backend:app` | feat/S2.1 | **B** |
| S2.4 | `answering`: `Submission`; `OpenQuestion`, `SubmitAnswer` (Submission + undecided Evaluation + `SubmissionReceived` outbox row in **one** transaction); JdbcClient writer with `ON CONFLICT DO NOTHING` | feat/S2.1 + S2.3 | **B** |
| S2.7 | `platform` relay v1: drain in seq order → enqueue grading job → project → mark published. Spec the crash windows hard: replay after crash, crash mid-batch, duplicate enqueue tolerated | feat/S2.3 + S2.5 | **B** |

Concurrency: 6, then 3. **Demo:** learner joins by code on a phone and submits; an undecided
Evaluation row exists; the grading job is visible in the RabbitMQ management UI.

### M3 — Grading pipeline

`S3.0` contract · `S3.1` Evaluation state machine + Verdict/Evidence VOs · `S3.2` `ILlmGrader` +
OpenRouter adapter + WireMock · `S3.3` `ProposeEvaluation` / `AbandonGrading` /
`RetryAbandonedGradings` · `S3.4` RabbitMQ consume (quorum queue, `delivery-limit`, DLX) · `S3.5` SQS
consume · `S3.6` `EvaluationWorkQueueContract` in `testFixtures` + both subclasses · `S3.7` projector
v2 (triage read model, coverage denominators, identical-evidence flag) · `S3.8` `ISessionNotifier` +
PG NOTIFY + non-pooled listener + WebSocket · `S3.9` FE live triage screen.

`S3.1 ∥ S3.2 ∥ S3.8 ∥ S3.9`, then `S3.3 ∥ S3.4 ∥ S3.5 ∥ S3.7`, then `S3.6`.

### M4 — Decision loop (the full classroom demo)

`S4.0` contract · `S4.1` triage use cases (Override / Release / ReleaseAll / Discard) · `S4.2`
`CloseQuestion` (ends answering **and** reveals criteria to all participants) · `S4.3` `EndSession`
(ADR-0010 blocking) + `ExpireSessions` · `S4.4` learner read model, two rendering states per
Evaluation · `S4.5` learner WebSocket (token handshake) · `S4.6` controller contract tests (commands
return new state) · `S4.7`–`S4.9` FE triage actions / close + end modals / learner feedback view ·
`S4.10` Playwright E2E smoke.

### M5 — Interchangeability (shrunk, per §1.4)

`S5.1` `KEEPUP_QUEUE` conditional wiring · `S5.2` contract suite green on both legs in CI ·
`S5.3` live `KEEPUP_QUEUE` flip on staging during a running session.

### M6 — Learner accounts, courses, registration, claim

`S6.0` contract · `S6.1` `LearnerAccount` domain + ports · `S6.2` Register / Verify / Authenticate /
Reset · `S6.3` Spring Mail SMTP adapter + MailHog · `S6.4` `Course` aggregate + course use cases ·
`S6.5` one-session grace guard in `JoinSession` · `S6.6` `ClaimParticipation` · `S6.7` registration
orchestrator in `:backend:app` · `S6.8` course radar read model + projector · `S6.9`–`S6.11` FE.

### M7 — Sharing & import

`S7.1` sharing domain + Share / Unshare / Import / Browse · `S7.2` `ITrainerDirectory` + adapter ·
`S7.3` FE public gallery, import, lineage.

### M8 — Ops hardening

`S8.1` outbox pruning + Spring Session cleanup · `S8.2` prod compose hardening (Caddy WebSocket
upgrade, web ×2) · `S8.3` Postgres backups · `S8.4` login rate limiting · `S8.5` AWS key rotation
runbook · `S8.6` Gradle dependency-verification metadata (`verification-metadata.xml`, sha256).
Deferred here on purpose: it is a single shared file that every dependency bump must regenerate, so
committing it during M1–M7 would serialise every parallel slice that adds a dependency (a §5 hot
file). Land it once the dependency set has stopped moving.

> M3–M8 are slice *names*, not file manifests, on purpose. **Expand a milestone's slices into full
> packets at its kickoff, not before** — a file-level ownership map written six milestones early is
> fiction, and fiction is what makes agents step on each other.

---

## 7. Docker images

Two images, both `linux/amd64`, both built **only in CI** — never on the Mac, never on the VPS.

**`keepup-backend`** — one image, three roles, selected at runtime by `KEEPUP_ROLES` (plan §5):

1. **build**: JDK 21 → `bootJar` (Gradle cache mounted from the Actions cache).
2. **extract**: `java -Djarmode=tools -jar app.jar extract --layers` — layered so dependencies cache
   across builds and only the application layer changes per commit.
3. **runtime**: `eclipse-temurin:21-jre-alpine`, non-root user, no shell tooling, layers copied in
   dependency→application order.

Per-role heap comes from the deploy environment, not the image (`web -Xmx384m`, `worker -Xmx256m`,
`relay -Xmx160m`).

**`keepup-frontend`** — `node:24-alpine` build → `nginx:alpine` runtime serving the Angular `dist`.
Separate from the backend so the frontend CI job stays fully independent and a UI change does not
rebuild or redeploy the JVM.

Caddy (already on the VPS, Coolify-managed) reverse-proxies `/` → frontend and `/api` + `/ws` →
backend web, **with WebSocket upgrade** — that last part is S8.2, and it is easy to forget until the
live triage screen silently stops updating.

*Cross-arch:* local compose builds arm64 natively on the M4; CI builds amd64 natively on
`ubuntu-latest`. No QEMU, no emulation. Nothing in this stack has native dependencies, so the two
produce equivalent artifacts — but **the arm64 image is a dev convenience and is never deployed.**

---

## 8. CI/CD

`.github/workflows/`, owned by S0.5. Path-filtered, with concurrency groups that cancel superseded
runs.

**On `pull_request` → `staging` or `master`:**

| Job | Does | Gate |
|---|---|---|
| `backend-test` | Gradle build, unit + use-case specs, Testcontainers (PG 15.8, RabbitMQ 4), **ArchUnit** | required |
| `frontend-test` | `npm ci`, lint, unit, build | required |
| `raw-html-gate` | Greps `frontend/src` for a **broad** sink set and fails on any hit: `innerHTML`, `outerHTML`, `insertAdjacentHTML`, `bypassSecurityTrust` (the whole family — `Html`/`Script`/`Style`/`Url`/`ResourceUrl`, not just `Html`), `SecurityContext.NONE`, `createContextualFragment`, `DOMParser`, `srcdoc`. **Deliberately not an ESLint rule**: a lint rule is defeatable by a one-line `eslint-disable` comment *and* by AST evasion the rule's selectors don't match (computed member access, aliasing, destructuring) — the PR#3 review proved both. This gate guards Risk #7 — LLM-extracted evidence, quoted verbatim from learner-submitted text, rendered into a trainer's browser. It must not be silenceable from inside the file it guards, and it greps prefixes precisely because an AST allow-list is never complete. The ESLint rule stays as the fast local signal; the grep gate is the wall. The strategic fix — CSP + `require-trusted-types-for 'script'` — lands with the evidence-rendering feature (M3 S3.9 / M4), converting this deny-list into a browser-enforced allow-list. | required |
| `secrets-scan` | gitleaks over the diff **and** full history | required |

**On `push` → `staging` / `master` (and `workflow_dispatch`):**

| Job | Does |
|---|---|
| `sqs-contract` | ADR-0008 contract suite against the **real eu-west-3 test queue pair** (short visibility, so give-up tests finish in seconds). Env-gated on credentials. |
| `build-push` | Both images, `linux/amd64`, pushed to GHCR tagged `<sha>`. |
| `deploy` | Calls the Coolify deploy webhook with the `<sha>` tag. |
| `e2e` | *(from M4)* Playwright against the deployed staging URL, WireMocked OpenRouter. |

**Promotion to production re-tags the digest staging validated.** It does not rebuild — there is no
`build` step on the `master` path, only `deploy`.

**Because the repository is public**, jobs needing secrets (`sqs-contract`, `build-push`, `deploy`)
run **only on `push` and `workflow_dispatch`, never on `pull_request`**. GitHub already withholds
secrets from fork PRs, but the rule is written down so nobody later "fixes" the gating by reaching
for `pull_request_target` — which would hand a fork's code the AWS credentials.

**Contract with S0.6 (AWS OIDC):** the SQS role's trust policy scopes its subject to
`repo:RoTour/keepup:environment:ci`, not to the whole repo. So **every job that assumes the AWS role
(`sqs-contract`) MUST declare `environment: ci`** and `permissions: id-token: write` — otherwise the
minted OIDC token's subject won't match the trust policy and `AssumeRoleWithWebIdentity` fails
closed. That failure is the safe direction (no access on misconfiguration), but it is also the
confusing one: it surfaces as a generic "not authorized to perform sts:AssumeRoleWithWebIdentity"
that reads like a policy bug when it actually means the job forgot its `environment`.

---

## 9. Secrets — the build-in-public rules

The repository is public. Every rule below assumes an adversary reads every commit.

- **Nothing secret is ever committed, and nothing secret is ever baked into an image.** All
  credentials — `DATABASE_URL`, RabbitMQ, `OPENROUTER_API_KEY`, AWS, SMTP — are Coolify environment
  variables at runtime and GitHub Actions secrets at build time. Never a file in the repo, never an
  `ARG`, never a build-time `ENV`.
- **`.dockerignore` and `.gitignore` both exclude**: `.env*`, `**/application-local.yml`, `*.pem`,
  `**/secrets/`, `infra/terraform/*.tfstate*`, `.terraform/`, `.git/`.
- **Terraform state lives in S3, not in the repo** (S0.6). A committed `.tfstate` publishes the IAM
  user ARN, the queue URLs, and whatever else Terraform happened to record. This is the single most
  likely accidental leak in the whole plan — S3 backend from the first `terraform init`, not later.
- **gitleaks is a required check**, over the diff *and* the full history. A secret that reaches a
  public repo is compromised the moment it lands; rotation, not deletion, is the remedy. Force-push
  does not un-publish it.
- `scripts/db-tunnel.sh` references only an SSH *alias*. Host, user, and key stay in `~/.ssh/config`,
  which is never committed.
- **The `OPENROUTER_API_KEY` is the one to watch.** It is spendable, it lives in the worker role, and
  ADR-0011 already accepts that attacker-controlled text reaches the LLM. Separate keys per
  environment, with spend caps.

---

## 10. Local access to the staging / production database

```bash
./scripts/db-tunnel.sh          # localhost:5432  -> VPS 127.0.0.1:5432
./scripts/db-tunnel.sh 55432    # if dev compose already owns 5432
```

Remote `5432` is the `supabase-db` container's direct port. **Do not repoint this at Supavisor** —
see §1.1. Postgres is not publicly exposed; the tunnel is the only path in, deliberately.

---

## 11. Open items

1. **Coolify deploy-webhook mechanics** — token, per-app URL, how it pins an image digest — are not
   yet confirmed. Needed by S0.5 and S0.10.
2. **`staging` and `prod` share one Postgres instance.** A runaway staging query degrades production.
   Acceptable at classroom scale; revisit if it ever bites.
3. **Spring Boot 4.1.0 is very recent.** If the ecosystem lags (Flyway, Spring AMQP, AWS SDK v2,
   Testcontainers, ArchUnit), the fallback is the 3.5.x line. S0.1 verifies this and reports.
