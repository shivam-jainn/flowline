#!/usr/bin/env bash
# add-godaddy-dns.sh — point flowline.shivamja.in at Vercel (CNAME, GoDaddy v3 API).
# Usage: ./infra/scripts/add-godaddy-dns.sh
#
# Auth is a GoDaddy Personal Access Token (PAT, Bearer). Classic sso-key
# (key:secret) is deprecated for Domains and does NOT work with v3.
# Make one at developer.godaddy.com (Token Name + scopes below, production):
#   domains.domain:read   (read records)
#   domains.dns:update    (create/update records)
# Store it in the vault: folder `Godaddy`, item `bw-1-dns` (password = PAT).
# The script pulls it via BW_SESSION; or export GODADDY_PAT directly.
# Manual fallback (no token): GoDaddy dashboard -> shivamja.in -> DNS ->
#   Type CNAME, Name flowline, Value 7dd8acd18b97be7a.vercel-dns-017.com., TTL 1h
set -euo pipefail

DOMAIN="shivamja.in"
SUBDOMAIN="flowline"
# Recommended by `vercel domains verify flowline.shivamja.in` (rank 1).
# Fallback: cname.vercel-dns.com.
TARGET="${GODADDY_TARGET:-7dd8acd18b97be7a.vercel-dns-017.com.}"
VAULT_ITEM="${GODADDY_VAULT_ITEM:-bw-1-dns}"

if [[ -z "${GODADDY_PAT:-}" && -n "${BW_SESSION:-}" ]]; then
  GODADDY_PAT="$(bw get password "$VAULT_ITEM" --session "$BW_SESSION" 2>/dev/null || true)"
fi
: "${GODADDY_PAT:?missing PAT — vault item '$VAULT_ITEM' + BW_SESSION, or export GODADDY_PAT}"

echo "reading current CNAME $SUBDOMAIN.$DOMAIN"
curl -sS "https://api.godaddy.com/v3/domains/zones/$DOMAIN/dns-records?type=CNAME&name=$SUBDOMAIN" \
  -H "Authorization: Bearer $GODADDY_PAT" -H "Accept: application/json" | head -c 500
echo

echo "setting CNAME $SUBDOMAIN.$DOMAIN -> $TARGET"
curl -sS -X POST "https://api.godaddy.com/v3/domains/zones/$DOMAIN/dns-records" \
  -H "Authorization: Bearer $GODADDY_PAT" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$SUBDOMAIN\",\"type\":\"CNAME\",\"data\":\"$TARGET\",\"ttl\":3600}"
echo
echo "verify: vercel domains verify flowline.shivamja.in"
