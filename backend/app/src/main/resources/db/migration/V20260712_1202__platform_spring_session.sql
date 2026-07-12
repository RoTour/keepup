-- V1 / platform Spring Session — the canonical Spring Session JDBC schema.
--
-- Verbatim column/type/constraint/index definitions from Spring Session 4.1.0
-- (spring-session-jdbc schema-postgresql.sql), placed in the `platform` schema
-- because the web session is cross-cutting infrastructure with no domain (ADR-0018).
-- The shipped DDL uses UNqualified names (it resolves against search_path, it does
-- NOT assume `public`), so qualifying them into `platform` is safe and changes
-- nothing Spring Session sees.
--
-- These tables exist ONLY because Flyway made them: Spring Session's auto-DDL is
-- OFF (ADR-0018), so any drift between this schema and what the app expects fails
-- the container at boot instead of mid-class. The app must be pointed at
-- `platform.SPRING_SESSION` (spring.session.jdbc.table-name / search_path) in a
-- later slice — that is app config, not this migration.
--
-- Structure (columns, types, PKs, FKs, index names) is kept EXACTLY as shipped so
-- Spring Session recognises it; only `IF NOT EXISTS` and the `platform.` prefix are
-- added, neither of which alters the recognised schema.

CREATE TABLE IF NOT EXISTS platform.SPRING_SESSION (
	PRIMARY_ID CHAR(36) NOT NULL,
	SESSION_ID CHAR(36) NOT NULL,
	CREATION_TIME BIGINT NOT NULL,
	LAST_ACCESS_TIME BIGINT NOT NULL,
	MAX_INACTIVE_INTERVAL INT NOT NULL,
	EXPIRY_TIME BIGINT NOT NULL,
	PRINCIPAL_NAME VARCHAR(100),
	CONSTRAINT SPRING_SESSION_PK PRIMARY KEY (PRIMARY_ID)
);

CREATE UNIQUE INDEX IF NOT EXISTS SPRING_SESSION_IX1 ON platform.SPRING_SESSION (SESSION_ID);
CREATE INDEX IF NOT EXISTS SPRING_SESSION_IX2 ON platform.SPRING_SESSION (EXPIRY_TIME);
CREATE INDEX IF NOT EXISTS SPRING_SESSION_IX3 ON platform.SPRING_SESSION (PRINCIPAL_NAME);

CREATE TABLE IF NOT EXISTS platform.SPRING_SESSION_ATTRIBUTES (
	SESSION_PRIMARY_ID CHAR(36) NOT NULL,
	ATTRIBUTE_NAME VARCHAR(200) NOT NULL,
	ATTRIBUTE_BYTES BYTEA NOT NULL,
	CONSTRAINT SPRING_SESSION_ATTRIBUTES_PK PRIMARY KEY (SESSION_PRIMARY_ID, ATTRIBUTE_NAME),
	CONSTRAINT SPRING_SESSION_ATTRIBUTES_FK FOREIGN KEY (SESSION_PRIMARY_ID) REFERENCES platform.SPRING_SESSION(PRIMARY_ID) ON DELETE CASCADE
);
