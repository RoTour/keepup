# Local development backing services

Postgres, RabbitMQ and MailHog for local development.

This stack contains **backing services only**. The application and database
migration services are not here yet — they arrive with the slice that introduces
the Dockerfiles.

## Bring it up

```bash
cd infra/docker
cp .env.example .env          # .env is gitignored
docker compose -f compose.dev.yml up -d
```

Everything is up when all three report `healthy`:

```bash
docker compose -f compose.dev.yml ps
```

## What you get

| Service  | Host address                                     | Credentials       |
| -------- | ------------------------------------------------ | ----------------- |
| Postgres | `localhost:5432`, database `keepup`              | `keepup`/`keepup` |
| RabbitMQ | `localhost:5672` (AMQP)                          | `keepup`/`keepup` |
| RabbitMQ | <http://localhost:15672> (management UI)         | `keepup`/`keepup` |
| MailHog  | `localhost:1025` (SMTP), <http://localhost:8025> | none              |

Credentials are local-development defaults from `.env.example`, and are not
secrets. Override them in `.env` if you like.

MailHog captures every mail the app sends and delivers none of them — read them
in its web UI.

## Schemas

On first start Postgres creates one schema per bounded context: `authoring`,
`delivery`, `identity`, `platform`.

```bash
docker compose -f compose.dev.yml exec postgres \
  psql -U keepup -d keepup -c '\dn'
```

Only the schemas are created here. **Tables are owned by Flyway migrations**, not
by this stack.

The init script runs *once*, when the data volume is first created. If you change
it, you must recreate the volume (`down -v`) for it to take effect.

## Tear it down

```bash
docker compose -f compose.dev.yml down     # stop, keep data
docker compose -f compose.dev.yml down -v  # stop and delete data
```

## Notes

- **Postgres is pinned to 15.8** to match production (Supabase
  `supabase/postgres:15.8.1.085`). Dev, Testcontainers and prod must run the same
  Postgres. Do not bump it here alone.
- **MailHog is amd64-only** — it has no arm64 image — so on Apple Silicon it runs
  under emulation. This is expected and works. The maintained multi-arch
  alternative, if it ever becomes annoying, is `axllent/mailpit` (same ports).
- The stack uses the compose project name `keepup-dev`, so its network and
  volumes will not collide with other stacks on your machine.
