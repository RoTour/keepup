-- keepup — bounded-context schemas.
--
-- Schemas ONLY. No table DDL here: tables are owned by Flyway migrations.
-- This script runs once, when Postgres initialises an empty data volume.
--
-- It executes as POSTGRES_USER against POSTGRES_DB, so each schema is owned by
-- the application role and needs no extra grants.

CREATE SCHEMA IF NOT EXISTS authoring;
CREATE SCHEMA IF NOT EXISTS delivery;
CREATE SCHEMA IF NOT EXISTS identity;
CREATE SCHEMA IF NOT EXISTS platform;
