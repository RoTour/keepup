-- V1 / delivery outbox + projection cursor — the transactional outbox and the
-- single forward-only cursor the relay drains it with.
--
-- SCHEMA PLACEMENT: `delivery`, not `platform`.
--   ADR-0006 and ADR-0016 make this data Delivery's. ADR-0016: "That machinery is
--   Delivery's, and it stops at Delivery's border" and "The port is named
--   IDeliveryOutbox, not IOutbox. That is the decision, spelled in a type name."
--   The rows carry Delivery domain events (e.g. SubmissionReceived, ADR-0017) and
--   the cursor drives Delivery's read-model projector. ADR-0016 does say the
--   *platform module* hosts the relay code / LISTEN-NOTIFY / advisory-lock helpers
--   as generic infrastructure — but that is CODE placement with zero domain
--   knowledge, not where the DATA lives, and "no other context is entitled to
--   assume it will" serve them. So the tables sit in `delivery`; only the
--   context-agnostic web-session tables go in `platform` (see V*_1202).
--
-- Persistence idiom: JdbcClient, never JPA (ADR-0022) — the outbox and the
-- projections have no aggregate. This migration owns only the DDL.

-- ---------------------------------------------------------------------------
-- delivery.outbox — one row per domain event, appended inside the command's own
-- transaction (ADR-0006: the write path and the event commit together, closing
-- the dual-write window). Drained in seq order by the single relay, which
-- projects, notifies/enqueues, then marks the row published (ADR-0017).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS delivery.outbox (
    -- seq is the ordering key. BIGSERIAL assigns at INSERT, NOT at COMMIT, so on
    -- its own seq order is NOT commit order (ADR-0017). The writer closes that gap
    -- by taking pg_advisory_xact_lock on a fixed key BEFORE appending, inside the
    -- command transaction, so the lower seq is always the earlier commit. That
    -- lock is application code; this column is the thing its guarantee attaches to,
    -- and the cursor below depends on it holding. Do not remove the lock (ADR-0017).
    seq          BIGSERIAL     PRIMARY KEY,

    -- The event kind the relay dispatches on: a 'SubmissionReceived' row is what
    -- makes the relay enqueue an IEvaluationWorkQueue job (ADR-0017).
    event_type   TEXT          NOT NULL,

    -- The event payload the row carries (ADR-0006). JSONB: the read-model projector
    -- and the enqueue step read fields out of it; no aggregate is ever loaded.
    payload      JSONB         NOT NULL,

    -- When the row was appended. Supports pruning of the growing outbox (ADR-0006)
    -- and ordering diagnostics.
    occurred_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),

    -- NULL until the relay has projected + notified/enqueued this row and marked it
    -- published/drained (ADR-0006/0017). Set last, so a crash before it replays the
    -- row rather than losing it.
    published_at TIMESTAMPTZ
);

-- ---------------------------------------------------------------------------
-- delivery.projection_cursor — the relay's single, global, forward-only cursor
-- (ADR-0006 "a last-applied seq cursor"; ADR-0017 "the cursor is global"). The
-- relay drains `WHERE seq > last_seq ORDER BY seq` and advances last_seq strictly.
-- The singleton constraint (only value TRUE, and it is the PK) makes a second
-- cursor row impossible: the global ordering guarantee requires exactly one
-- cursor, so the DDL forbids more than one (ADR-0017).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS delivery.projection_cursor (
    id         BOOLEAN      NOT NULL DEFAULT TRUE,
    last_seq   BIGINT       NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
    CONSTRAINT projection_cursor_pk        PRIMARY KEY (id),
    CONSTRAINT projection_cursor_singleton CHECK (id)
);

-- Seed the one cursor row at seq 0, so the first drain (`WHERE seq > 0`) picks up
-- outbox seq 1. Idempotent: a re-run leaves an already-advanced cursor untouched.
INSERT INTO delivery.projection_cursor (id, last_seq)
VALUES (TRUE, 0)
ON CONFLICT (id) DO NOTHING;
