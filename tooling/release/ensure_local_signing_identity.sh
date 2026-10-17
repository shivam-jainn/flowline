#!/usr/bin/env bash
# Checks for an Apple-issued development signing identity. Only those carry a
# TeamIdentifier, which is what makes macOS TCC (Screen Recording /
# Accessibility) grants survive rebuilds. Ad-hoc (`-`) and self-signed certs
# are keyed by binary hash, so every rebuild looks like a new app and the
# grants get dropped — that loop cannot be scripted away, it needs a real
# identity (free Apple ID, no paid Developer Program for local signing).
set -euo pipefail

if security find-identity -v -p codesigning 2>/dev/null | grep -qE "Apple Development|Mac Developer|Developer ID Application"; then
    echo "✅ Apple-issued signing identity found:"
    security find-identity -v -p codesigning 2>/dev/null | grep -E "Apple Development|Mac Developer|Developer ID Application" | head -3
    echo "Rebuilds will keep TCC grants. Nothing to do."
    exit 0
fi

cat <<'EOF'
❌ No Apple-issued development identity. One-time fix (free, ~2 min):

  1. Open Xcode → Settings… → Accounts → + → Apple ID → sign in
     (a free Apple ID is enough — no paid Developer Program needed
     for local development signing).
  2. Xcode automatically mints an "Apple Development" certificate.
  3. Re-run:  make sign-setup   (should now print ✅)
  4. Then:    make test-dev     (fresh build, signed with your team)
  5. Grant Screen Recording + Accessibility once, `make run` to relaunch.

Why not a script-made cert: only Apple-issued certs embed a
TeamIdentifier. macOS keys TCC grants on (TeamID, BundleID) for those,
but on the binary hash for ad-hoc/self-signed — so script-made certs
rebuild the same grant-wiping loop. (Same answer as the Apple dev forums
give for "permissions reset on every build".)

NOTE: an old stale "StepIt Local Dev" self-signed cert may exist in your
login keychain from an earlier attempt. It is now unused and safe to
ignore (or delete it in Keychain Access).
EOF
exit 1
