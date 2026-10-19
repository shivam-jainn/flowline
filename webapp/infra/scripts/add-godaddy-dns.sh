#!/usr/bin/env bash
# add-godaddy-dns.sh — point flowline.shivamja.in at Vercel (CNAME).
# Usage: GODADDY_API_KEY=... GODADDY_API_SECRET=... ./infra/scripts/add-godaddy-dns.sh
#
# Keys: https://developer.godaddy.com/keys (API key + secret, production env).
# Store them in the vault when you have them, e.g. items:
#   folder `flowline-prod` / item `godaddy-api-key` (+ `godaddy-api-secret`),
# then: export GODADDY_API_KEY="$(bw get password godaddy-api-key)"
# Manual fallback (2 min, no keys): GoDaddy dashboard -> shivamja.in -> DNS ->
#   Type CNAME, Name flowline, Value 7dd8acd18b97be7a.vercel-dns-017.com., TTL 1h
set -euo pipefail

DOMAIN="shivamja.in"
SUBDOMAIN="flowline"
# Recommended by `vercel domains verify flowline.shivamja.in` (rank 1).
# Fallback: cname.vercel-dns.com.
TARGET="${GODADDY_TARGET:-7dd8acd18b97be7a.vercel-dns-017.com.}"

# Vault-first: pull keys from Vaultwarden when env vars are unset.
# Expected items: folder `flowline-prod`, `godaddy-api-key` + `godaddy-api-secret`.
if [[ -z "${GODADDY_API_KEY:-}" && -n "${BW_SESSION:-}" ]]; then
  GODADDY_API_KEY="$(bw get password godaddy-api-key --session "$BW_SESSION" 2>/dev/null || true)"
fi
if [[ -z "${GODADDY_API_SECRET:-}" && -n "${BW_SESSION:-}" ]]; then
  GODADDY_API_SECRET="$(bw get password godaddy-api-secret --session "$BW_SESSION" 2>/dev/null || true)"
fi

: "${GODADDY_API_KEY:?set GODADDY_API_KEY or vault item godaddy-api-key + BW_SESSION}"
: "${GODADDY_API_SECRET:?set GODADDY_API_SECRET or vault item godaddy-api-secret + BW_SESSION}"

echo "setting CNAME $SUBDOMAIN.$DOMAIN -> $TARGET"
curl -sS -X PUT "https://api.godaddy.com/v1/domains/$DOMAIN/records/CNAME/$SUBDOMAIN" \
  -H "Authorization: sso-key $GODADDY_API_KEY:$GODADDY_API_SECRET" \
  -H "Content-Type: application/json" \
  -d "[{\"data\":\"$TARGET\",\"ttl\":3600}]"
echo
echo "verify: vercel domains verify flowline.shivamja.in"
