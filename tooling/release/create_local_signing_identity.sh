#!/usr/bin/env bash
# Creates a persistent, stable local code signing identity in the user's login keychain.
#
# WHY THIS WORKS:
# Ad-hoc signing (`-s -`) keys macOS TCC permissions to the binary hash (cdhash),
# which changes on every single rebuild.
# A stable local self-signed identity embeds a persistent certificate authority
# requirement (`certificate root = H"..."`), so the designated requirement
# remains IDENTICAL across rebuilds, preserving Screen Recording and Accessibility grants!
set -euo pipefail

CERT_NAME="StepIt Development"
KEYCHAIN="${HOME}/Library/Keychains/login.keychain-db"

if security find-certificate -c "${CERT_NAME}" "${KEYCHAIN}" >/dev/null 2>&1; then
    echo "✅ Stable signing identity '${CERT_NAME}' already exists in ${KEYCHAIN}."
    exit 0
fi

echo "⚡️ Generating stable local code signing identity: ${CERT_NAME}..."

TMP_DIR="$(mktemp -d -t stepit_cert_XXXXXX)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat << 'EOF' > "${TMP_DIR}/cert.cnf"
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
CN = StepIt Development
O = StepIt Local Dev
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
    -passout pass:stepit 2>/dev/null

# Import into the user's login keychain with -A (allow codesign without prompting)
security import "${TMP_DIR}/dev.p12" \
    -k "${KEYCHAIN}" \
    -P stepit \
    -A \
    -T /usr/bin/codesign \
    -T /usr/bin/security

echo "✅ Successfully imported '${CERT_NAME}' into ${KEYCHAIN}."
echo "👉 Note: When codesign runs for the first time, click 'Always Allow' on the macOS prompt."
