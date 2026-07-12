# Local development backing services

Postgres, RabbitMQ and Mailpit for local development.

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
| Mailpit  | `localhost:1025` (SMTP), <http://localhost:8025> | none              |

Credentials are local-development defaults from `.env.example`, and are not
secrets. Override them in `.env` if you like.

Mailpit captures every mail the app sends and delivers none of them — read them
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
- **Mailpit, not MailHog.** MailHog is archived upstream and publishes an
  amd64-only image, so it would run under emulation on Apple Silicon. Mailpit is
  maintained, multi-arch (native on arm64) and a drop-in on the same ports. Every
  image in this stack runs natively — there is no `platform:` override anywhere.
- **RabbitMQ uses an explicit user, not `guest`.** This is deliberate; see the
  comment in `compose.dev.yml` before changing it.
- The stack uses the compose project name `keepup-dev`, so its network and
  volumes will not collide with other stacks on your machine.
- If a port collides with something already on your machine (5432 is a common
  one), override it in `.env` — every host port is parameterised.
