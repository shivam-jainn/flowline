#!/usr/bin/env bash
# One-time signing setup for StepIt development.
#
# WHY THIS EXISTS (read from Apple's own SDK + tools, not forums):
# - CGWindow.h (CoreGraphics SDK headers): capture access is per-PROCESS,
#   granted via user prompt ("Requests ... if absent, potentially prompting").
# - AXUIElement.h (HIServices SDK headers): trust is per-PROCESS
#   ("Returns whether the CURRENT PROCESS is a trusted accessibility client").
# - ScreenCaptureKit headers: other apps' content needs "user consent via TCC".
# - `man tccutil`: the ONLY command is `reset`. There is no grant command —
#   Apple reserves consent to the user in Settings/prompts. No script on earth
#   can click "grant" for you, so Settings gets touched exactly ONCE more.
#
# WHAT MAKES THAT "ONCE" STICK: an Apple-issued identity embeds a
# TeamIdentifier, and TCC keys those grants on (TeamID, BundleID) — rebuilds
# keep working. Ad-hoc (`-`) and self-signed carry TeamIdentifier=not set, so
# TCC keys them on the binary hash and EVERY rebuild looks like a new app.
# This script proves which case you're in by test-signing a scratch binary.
set -euo pipefail

IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n -e 's/^.*"\(Apple Development[^"]*\)".*/\1/p' \
             -e 's/^.*"\(Mac Developer[^"]*\)".*/\1/p' \
             -e 's/^.*"\(Developer ID Application[^"]*\)".*/\1/p' \
    | head -1)"

if [ -z "${IDENTITY}" ]; then
    # Orphan cert, no private key: Xcode uploaded a CSR and got the cert back,
    # but the keypair never landed in the keychain (no identity = no signing).
    # Only fix is revoke + recreate so a fresh keypair is generated.
    if security find-certificate -c "Apple Development" >/dev/null 2>&1; then
        cat <<'EOF'
⚠️  Found an "Apple Development" CERTIFICATE but its PRIVATE KEY is missing
    from the keychain — so there is no usable signing identity. Fix:

  1. Xcode → Settings… → Accounts → select your Apple ID → your Team →
     Manage Certificates…
  2. Select the "Apple Development" entry → – (delete) → confirm.
     (It was created today and never used — safe to revoke.)
  3. Click + → Apple Development (fresh keypair + certificate).
  4. Verify:  security find-identity -v -p codesigning
     (must show "1 valid identity found", not 0)
  5. Re-run:  make sign-setup
EOF
        exit 1
    fi
    cat <<'EOF'
❌ No Apple-issued development identity. One-time fix (free, ~2 min):

  1. Open Xcode → Settings… (⌘,) → Accounts → + → Apple ID → sign in
     (a free Apple ID is enough — no paid Developer Program needed
     for local development signing).
  2. Xcode mints an "Apple Development" certificate automatically.
  3. Re-run:  make sign-setup   (should print ✅ STABLE below)
  4. Then:    make test-dev     (fresh build, signed with your team)
  5. Grant Screen Recording + Accessibility ONCE, `make run` to relaunch.

If Xcode insists you "already have" a certificate but none works
(orphan without a private key): restart your Mac first (clears Xcode's
portal cache and reloads the keychain), then Manage Certificates → –
the dead entry → + → Apple Development. Also check for a pending
Developer Agreement banner at account.apple.com — Xcode silently
refuses cert operations until it is accepted.

After that, rebuilds keep working and you never open Settings again.
EOF
    exit 1
fi

# Prove stability instead of asserting it: sign a scratch copy and read back
# the TeamIdentifier. (First use may prompt for keychain access — Always Allow.)
PROBE="$(mktemp -t stepit_sign_probe)"
cp /bin/ls "${PROBE}"
codesign --force --sign "${IDENTITY}" "${PROBE}" 2>/dev/null || true
TEAM="$(codesign -dv "${PROBE}" 2>&1 | sed -n 's/^TeamIdentifier=//p' || true)"
rm -f "${PROBE}"

echo "✅ Signing identity: ${IDENTITY}"
if [ -n "${TEAM}" ] && [ "${TEAM}" != "not set" ]; then
    echo "✅ TeamIdentifier=${TEAM} → STABLE: TCC grants survive rebuilds."
    echo "   Grant once, then never touch Settings again."
    exit 0
else
    echo "⚠️  TeamIdentifier not set — this identity will NOT survive rebuilds."
    exit 1
fi
