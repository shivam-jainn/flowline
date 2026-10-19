# Flowline waitlist webapp (Next.js)

Hero page is the waitlist form. Same copy as `landing/index.html` in the
OpenDesign project, rebuilt as a real app with an API.

## Run (dev with Postgres)

```bash
cd webapp
cp .env.example .env   # already has DATABASE_URL + WAITLIST_TABLE=waitlist_flowline
docker compose up -d db
npm install
npm run dev    # http://localhost:3000
```

Prod-like runs:

```bash
npm run build && npm run start -- --port 3102   # local prod build
docker compose --profile app up --build         # Docker prod (web + db)
```

## Waitlist storage

| Env | Backend | Config |
| --- | ------- | ------ |
| Local dev (no DB) | JSON file `webapp/data/waitlist.json` | unset `DATABASE_URL` — just run |
| Local dev (Postgres) | Postgres `waitlist_flowline` via `docker compose up -d db` | `DATABASE_URL` + `WAITLIST_TABLE=waitlist_flowline` in `.env` |
| Prod | Neon / Postgres (provider inferred from URL, like shipyard-web) | `DATABASE_URL` in `.env` (see `.env.example`) |

Table shape matches shipyard-web (`id, email UNIQUE, source, created_at`);
table is `waitlist_flowline` (`WAITLIST_TABLE` in `.env` and
`docker-compose.yml`, default `waitlist_flowline` in compose).

`GET /api/waitlist` returns `{ count, backend, table }`.
`POST /api/waitlist` with `{ "email", "source?" }` returns
`{ ok, duplicate, count }` (201 new, 200 duplicate).

## Prod DB via Pulumi

```bash
cd webapp/infra
npm install
pulumi stack init prod
pulumi config set neonApiKey <KEY> --secret
pulumi up
pulumi stack output databaseUrl --show-secrets   # -> ../.env as DATABASE_URL
```

Details in `infra/README.md`. No Kubernetes, no operators, no K8s
secrets — just Pulumi + Neon + `.env`.
