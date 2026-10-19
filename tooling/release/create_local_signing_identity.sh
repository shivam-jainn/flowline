#!/usr/bin/env bash
# Creates a DR-stable local code signing identity in the user's login keychain.
#
# WHAT THIS DOES:
# Ad-hoc signing (`-s -`) produces a cdhash-only designated requirement,
# which changes on every single rebuild.
# Signing with this self-signed identity produces a STABLE designated
# requirement (`identifier + certificate root = H"..."`), identical across
# rebuilds — strictly better than ad-hoc and verifiable with:
#   codesign -dr - platform/macos/.build/Flowline.app
#
# HONEST LIMIT:
# Only an Apple-issued identity (TeamIdentifier set) GUARANTEES TCC
# (Screen Recording / Accessibility) survival across rebuilds — macOS keys
# those grants on (TeamID, BundleID). With TeamIdentifier=not set, macOS
# still largely keys on binary hash, so treat this as best-effort.
# For zero Settings trips: Xcode + free Apple ID → Apple Development cert
# → `make sign-setup` reports STABLE.
set -euo pipefail

CERT_NAME="Flowline Development"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-certificate -c "${CERT_NAME}" "${KEYCHAIN}" >/dev/null 2>&1; then
    echo "✅ Stable signing identity '${CERT_NAME}' already exists in ${KEYCHAIN}."
    exit 0
fi

echo "⚡️ Generating stable local code signing identity: ${CERT_NAME}..."

TMP_DIR="$(mktemp -d -t flowline_cert_XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat << 'EOF' > "${TMP_DIR}/cert.cnf"
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
CN = Flowline Development
O = Flowline Local Dev
C = US

[codesign]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
subjectKeyIdentifier = hash
EOF

# Generate private key and self-signed certificate (valid for 10 years)
openssl req -new -x509 -nodes -days 3650 \
    -config "${TMP_DIR}/cert.cnf" \
    -extensions codesign \
    -newkey rsa:2048 \
    -keyout "${TMP_DIR}/dev.key" \
    -out "${TMP_DIR}/dev.crt" 2>/dev/null

# Export to PKCS#12 using legacy encryption for Apple Security framework compatibility
openssl pkcs12 -export -legacy \
    -inkey "${TMP_DIR}/dev.key" \
    -in "${TMP_DIR}/dev.crt" \
    -out "${TMP_DIR}/dev.p12" \
    -passout pass:flowline 2>/dev/null

# Import into the user's login keychain with -A (allow codesign without prompting)
security import "${TMP_DIR}/dev.p12" \
    -k "${KEYCHAIN}" \
    -P flowline \
    -A \
    -T /usr/bin/codesign \
    -T /usr/bin/security

echo "✅ Successfully imported '${CERT_NAME}' into ${KEYCHAIN}."
echo "👉 Note: When codesign runs for the first time, click 'Always Allow' on the macOS prompt."
