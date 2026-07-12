-- V1 / schemas — the four bounded-context schemas, owned by Flyway.
--
-- Flyway is the authoritative owner of the schema (ADR-0022). In dev these four
-- schemas are ALSO created by infra/docker/postgres/init/01-schemas.sql, which
-- runs once on an empty data volume — but staging and production databases are
-- created bare, with no init script, so Flyway must be able to create them too.
-- Hence CREATE SCHEMA IF NOT EXISTS: idempotent whether or not the init script
-- already ran, and correct on a bare database where it did not.
--
-- One schema per bounded context:
--   authoring — Quiz/Question/Criterion authoring (JPA aggregate + JdbcClient reads)
--   delivery  — the live Session: submissions, evaluations, the outbox + read model
--   identity  — accounts (Trainer / registered Learner)
--   platform  — cross-cutting infrastructure with zero domain knowledge
--               (web session tables here; outbox relay/LISTEN-NOTIFY code lives in
--                the platform *module*, but its data is Delivery's — see V*_1201)

CREATE SCHEMA IF NOT EXISTS authoring;
CREATE SCHEMA IF NOT EXISTS delivery;
CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS platform;
