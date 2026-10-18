#!/usr/bin/env bash
set -euo pipefail

echo "⚡️ Building Flowline macOS Application..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "${ROOT_DIR}"

# 1. Compile (FFI artifacts must exist: run `make ffi` first
#    on a clean checkout — same requirement as `make build`).
#    CONFIG=debug for the fast incremental dev loop (`make dev`);
#    default release for shippable bundles (`make test-dev`, DMG).
CONFIG="${CONFIG:-release}"
swift build --package-path "${ROOT_DIR}/platform/macos" -c "${CONFIG}"

BIN_PATH="${ROOT_DIR}/platform/macos/.build/${CONFIG}/flowline"
APP_DIR="${ROOT_DIR}/platform/macos/.build/Flowline.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

# Remember the previous binary hash: with ad-hoc signing ANY rebuild is a new
# identity to macOS, so a changed hash means previously granted TCC entries
# just died. Warn loudly at the end (Apple-signed builds are TeamID-keyed
# and immune — no warning needed there).
OLD_HASH="$(shasum "${MACOS_DIR}/Flowline" 2>/dev/null | cut -d' ' -f1 || true)"

rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

# 2. Copy Executable
cp "${BIN_PATH}" "${MACOS_DIR}/Flowline"
chmod +x "${MACOS_DIR}/Flowline"

# 3. Create Info.plist
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Flowline</string>
    <key>CFBundleIdentifier</key>
    <string>com.flowline.macos</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Flowline</string>
    <key>CFBundleDisplayName</key>
    <string>Flowline</string>
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
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Flowline requires screen recording access to capture workflow steps and generate documentation.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Flowline requires accessibility access to inspect UI elements under the cursor.</string>
</dict>
</plist>
EOF

# 4. Copy Icon
if [ -f "${ROOT_DIR}/platform/macos/Assets/AppIcon.icns" ]; then
    cp "${ROOT_DIR}/platform/macos/Assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# 4b. Copy "Open in" editor icons (platform/macos/Assets/Editors/*.png).
# NOTE: Xcode.png is deliberately excluded — Apple's third-party trademark
# guidelines forbid shipping Apple-owned icons without a written license.
# The Xcode row falls back to its SF Symbol + runtime NSWorkspace icon.
for icon in Cursor VSCode Zed SublimeText Nova; do
    if [ -f "${ROOT_DIR}/platform/macos/Assets/Editors/${icon}.png" ]; then
        cp "${ROOT_DIR}/platform/macos/Assets/Editors/${icon}.png" "${RESOURCES_DIR}/${icon}.png"
    fi
done

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
    # Stable local self-signed identity (survives rebuilds without an Apple Developer account).
    if security find-certificate -c "Flowline Development" >/dev/null 2>&1; then
        SIGN_IDENTITY="Flowline Development"
        echo "✅ Using stable local signing identity: Flowline Development"
    fi
fi
if [ -z "${SIGN_IDENTITY}" ]; then
    SIGN_IDENTITY="-"
    echo "⚠️  Ad-hoc signing: TCC grants will NOT survive rebuilds. Run 'tooling/release/create_local_signing_identity.sh' to fix."
fi
echo "Signing with identity: ${SIGN_IDENTITY}"
if command -v codesign >/dev/null 2>&1; then
    echo "Signing application bundle..."
    codesign --force --deep --sign "${SIGN_IDENTITY}" "${APP_DIR}" 2>/dev/null || true
fi

NEW_HASH="$(shasum "${MACOS_DIR}/Flowline" 2>/dev/null | cut -d' ' -f1 || true)"
if [ "${SIGN_IDENTITY}" = "-" ] && [ -n "${OLD_HASH}" ] && [ "${OLD_HASH}" != "${NEW_HASH}" ]; then
    echo "⚠️  Binary identity changed under ad-hoc signing — macOS treats this as a NEW app:"
    echo "   previously granted Screen Recording / Accessibility entries are now dead (Settings may still show them ON)."
    echo "   Re-grant both in Settings, then relaunch with 'make run' (no rebuild)."
fi

echo "✅ Flowline.app successfully bundled at: ${APP_DIR}"
