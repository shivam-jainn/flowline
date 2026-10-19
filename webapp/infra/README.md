# flowline-webapp infra (Pulumi + Neon)

TypeScript Pulumi project. Backend is local (`file://~`, state in `~/.pulumi/stacks`),
secrets provider is `passphrase` (`PULUMI_CONFIG_PASSPHRASE`, stored in
`~/.pulumi-passphrase`, chmod 600 — never commit it).

Stack: `dev-flowline` — **deployed** (project `spring-sunset-91245169`,
org `org-mute-snow-12829158`, region `aws-us-east-1`, PG `17`).
Resources: Project `flowline-waitlist` (main + `flowline` db + `flowline_app`
role) → Branch `dev-flowline` (inherits db/role) → Endpoint `read_write`.

## The loop (no copy-paste, ever)

Infra-managed secrets flow to the app automatically:

```bash
cd webapp/infra && pulumi up --stack dev-flowline --yes   # or --stack prod
cd ../.. && npm run env:dev    # writes webapp/.env.development (gitignored, 600)
npm run env:prod               # writes webapp/.env.production (needs prod deployed)
```

One-time manual secrets (Google OAuth clients — Google allows no API for
these, so this step is console + one CLI command, once per stack, forever):

```bash
pulumi config set --secret googleClientId <id> --stack dev-flowline
pulumi config set --secret googleClientSecret <secret> --stack dev-flowline
npm run env:dev   # picks them up alongside the Neon URL
```

Rules: generated `.env.*` files are gitignored and chmod 600 — the script
refuses to pretend otherwise. Source of truth is always the stack
(Pulumi.yaml + encrypted state), never the generated file.

## Use the database

```bash
pulumi stack output databaseUrl --show-secrets --stack dev-flowline
# -> paste as DATABASE_URL in webapp/.env (sslmode=require already included)
```

Local Postgres (`webapp/docker-compose.yml`) still works for day-to-day dev;
Neon is the shared/prod target.
