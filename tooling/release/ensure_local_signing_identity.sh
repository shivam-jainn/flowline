#!/usr/bin/env bash
# Ensures a persistent local code-signing identity exists so rebuilds keep
# the same signing identity and macOS TCC (Screen Recording / Accessibility)
# grants survive `make test-dev`. Ad-hoc (`-`) signatures change identity on
# every rebuild, which is what wipes grants in a loop.
set -euo pipefail

NAME="StepIt Local Dev"

# NB: `find-identity -p codesigning` only lists policy-trusted identities, so
# it hides our self-signed cert. Detect via the cert itself instead.
if security find-certificate -c "${NAME}" >/dev/null 2>&1; then
    echo "✅ Signing identity '${NAME}' already exists."
    exit 0
fi

echo "🔑 Creating persistent signing identity '${NAME}' (one-time)..."
TMP_DIR="$(mktemp -d -t stepit_sign)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cat > "${TMP_DIR}/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = ${NAME}
[ext]
extendedKeyUsage = codeSigning
keyUsage = digitalSignature
EOF

openssl req -x509 -newkey rsa:2048 \
    -keyout "${TMP_DIR}/key.pem" \
    -out "${TMP_DIR}/cert.pem" \
    -days 8250 -nodes \
    -config "${TMP_DIR}/openssl.cnf" 2>/dev/null

openssl pkcs12 -export -legacy \
    -out "${TMP_DIR}/identity.p12" \
    -inkey "${TMP_DIR}/key.pem" \
    -in "${TMP_DIR}/cert.pem" \
    -passout pass:stepit \
    -name "${NAME}"

security import "${TMP_DIR}/identity.p12" \
    -k "${HOME}/Library/Keychains/login.keychain-db" \
    -P stepit -T /usr/bin/codesign

# Best-effort: trust the cert for code signing so it also shows up under
# `find-identity -p codesigning`. Needs admin; harmless to skip (signing and
# TCC stability work without it — detection above uses the cert directly).
if [ -t 0 ]; then
    sudo security add-trusted-cert -d -r trustRoot -p codeSign \
        -k /Library/Keychains/System.keychain "${TMP_DIR}/cert.pem" 2>/dev/null || true
fi

echo "✅ Created '${NAME}'."
echo "ℹ️  If codesign prompts for keychain access on first build, choose 'Always Allow'."
