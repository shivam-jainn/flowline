#!/usr/bin/env bash
set -euo pipefail

echo "⚡️ Building StepIt macOS Application..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${ROOT_DIR}"

# 1. Compile Release Binary
swift build -c release

BIN_PATH="${ROOT_DIR}/.build/release/stepit"
APP_DIR="${ROOT_DIR}/.build/StepIt.app"
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
if [ -f "${ROOT_DIR}/Assets/AppIcon.icns" ]; then
    cp "${ROOT_DIR}/Assets/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# 4. Ad-hoc codesign
if command -v codesign >/dev/null 2>&1; then
    echo "Signing application bundle..."
    codesign --force --deep --sign - "${APP_DIR}" 2>/dev/null || true
fi

echo "✅ StepIt.app successfully bundled at: ${APP_DIR}"
