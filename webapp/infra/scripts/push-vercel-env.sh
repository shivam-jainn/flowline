#!/usr/bin/env bash
# push-vercel-env.sh — push app envs to Vercel from the vault (no copy-paste).
# Usage: push-vercel-env.sh [prod|dev-flowline]   (default: prod -> Vercel production)
#
# DATABASE_URL comes from Vaultwarden first, Pulumi stack output as fallback.
# Vault layout (env-wise folders):
#   flowline-dev  / flowline-neon-dev   (dev DATABASE_URL)
#   flowline-prod / flowline-neon-prod  (prod DATABASE_URL)
# Non-secret config (table name, public endpoint) is set as Vercel `config`.
set -euo pipefail

STACK="${1:-prod}"
INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$(cd "$INFRA_DIR/.." && pwd)"

if [[ "$STACK" == "prod" ]]; then
  VAULT_ITEM="flowline-neon-prod"
  VERCEL_ENV="production"
else
  VAULT_ITEM="flowline-neon-dev"
  VERCEL_ENV="preview"
fi

get_vault_url() {
  command -v bw >/dev/null 2>&1 || return 0
  [[ -z "${BW_SESSION:-}" ]] && return 0
  bw get password "$VAULT_ITEM" --session "$BW_SESSION" 2>/dev/null || true
}

get_pulumi_url() {
  if [[ -z "${PULUMI_CONFIG_PASSPHRASE:-}" && -f "$HOME/.pulumi-passphrase" ]]; then
    export PULUMI_CONFIG_PASSPHRASE
    PULUMI_CONFIG_PASSPHRASE="$(cat "$HOME/.pulumi-passphrase")"
  fi
  pulumi --cwd "$INFRA_DIR" stack output databaseUrl --show-secrets --stack "$STACK" 2>/dev/null || true
}

URL="$(get_vault_url)"
if [[ -n "$URL" ]]; then
  echo "info: DATABASE_URL from vault item '$VAULT_ITEM'" >&2
else
  echo "info: vault unavailable, falling back to Pulumi stack output" >&2
  URL="$(get_pulumi_url)"
fi
if [[ -z "$URL" ]]; then
  echo "error: no DATABASE_URL (vault + Pulumi both empty)" >&2
  exit 1
fi

cd "$APP_DIR"
printf '%s' "$URL" | tr -d '\n' | vercel env add DATABASE_URL "$VERCEL_ENV" --force --type secret --yes >/dev/null 2>&1
echo "ok: DATABASE_URL -> Vercel $VERCEL_ENV (secret)"
vercel env add WAITLIST_TABLE "$VERCEL_ENV" --force --type config --value waitlist_flowline --yes >/dev/null 2>&1
vercel env add NEXT_PUBLIC_WAITLIST_ENDPOINT "$VERCEL_ENV" --force --type config --value /api/waitlist --yes >/dev/null 2>&1
echo "ok: WAITLIST_TABLE + NEXT_PUBLIC_WAITLIST_ENDPOINT -> Vercel $VERCEL_ENV (config)"
echo "next: vercel --prod  (then set NEXT_PUBLIC_SITE_URL to the live URL and redeploy)"
