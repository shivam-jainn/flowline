#!/usr/bin/env bash
set -euo pipefail

echo "⚡️ Building StepIt macOS Application..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "${ROOT_DIR}"

# 1. Compile (FFI artifacts must exist: run `make ffi` first
#    on a clean checkout — same requirement as `make build`).
#    CONFIG=debug for the fast incremental dev loop (`make dev`);
#    default release for shippable bundles (`make test-dev`, DMG).
CONFIG="${CONFIG:-release}"
swift build --package-path "${ROOT_DIR}/platform/macos" -c "${CONFIG}"

BIN_PATH="${ROOT_DIR}/platform/macos/.build/${CONFIG}/stepit"
APP_DIR="${ROOT_DIR}/platform/macos/.build/StepIt.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 2. Copy Executable
cp "${BIN_PATH}" "${MACOS_DIR}/StepIt"
chmod +x "${MACOS_DIR}/StepIt"

# 3. Create Info.plist
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>StepIt</string>
    <key>CFBundleIdentifier</key>
    <string>com.stepit.macos</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>StepIt</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>StepIt requires screen recording access to capture workflow steps and generate documentation.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>StepIt requires accessibility access to inspect UI elements under the cursor.</string>
</dict>
</plist>
EOF

# 4. Copy Icon
if [ -f "${ROOT_DIR}/platform/macos/Assets/AppIcon.icns" ]; then
    cp "${ROOT_DIR}/platform/macos/Assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# 5. Copy the fixture tree (Playground web app used by the demo tooling)
if [ -d "${ROOT_DIR}/shared/fixtures/playground-web" ]; then
    mkdir -p "${RESOURCES_DIR}/Fixtures"
    cp -R "${ROOT_DIR}/shared/fixtures/playground-web" "${RESOURCES_DIR}/Fixtures/"
fi

# 6. Code signing. TCC (Screen Recording / Accessibility) survives rebuilds
# ONLY under an Apple-issued identity (TeamIdentifier set): ad-hoc and
# self-signed certs are hash-keyed, so every rebuild looks like a new app
# and macOS drops the grants.
# Override with: CODESIGN_IDENTITY="Apple Development: you@x.com" make bundle
SIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "${SIGN_IDENTITY}" ]; then
    # First Apple-issued development identity, if any (BSD-sed-safe: one
    # expression per cert kind).
    SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | sed -n -e 's/^.*"\(Apple Development[^"]*\)".*/\1/p' \
                 -e 's/^.*"\(Mac Developer[^"]*\)".*/\1/p' \
                 -e 's/^.*"\(Developer ID Application[^"]*\)".*/\1/p' \
        | head -1)"
fi
if [ -z "${SIGN_IDENTITY}" ]; then
    SIGN_IDENTITY="-"
    echo "⚠️  Ad-hoc signing: TCC grants will NOT survive rebuilds. Run 'make sign-setup' once (free Apple ID) to fix permanently."
fi
echo "Signing with identity: ${SIGN_IDENTITY}"
if command -v codesign >/dev/null 2>&1; then
    echo "Signing application bundle..."
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_DIR}" 2>/dev/null || true
fi

echo "✅ StepIt.app successfully bundled at: ${APP_DIR}"
