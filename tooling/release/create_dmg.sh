#!/usr/bin/env bash
set -euo pipefail

# Flowline DMG Release Builder — Brand Guidelines §06
# 540x400 window, flat warm canvas + mark watermark, one instruction one gesture.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

VERSION="${1:-1.0.0}"
APP_NAME="Flowline"
VOL_NAME="${APP_NAME}"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DIST_DIR="${ROOT_DIR}/dist"
BUILD_DIR="${ROOT_DIR}/platform/macos/.build"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
BG_IMAGE="${ROOT_DIR}/platform/macos/Assets/dmg/background.png"
BG_RETINA="${ROOT_DIR}/platform/macos/Assets/dmg/background@2x.png"
ICON_FILE="${ROOT_DIR}/platform/macos/Assets/AppIcon.icns"

echo "=================================================="
echo "⚡️ Building ${APP_NAME} v${VERSION} Release DMG"
echo "=================================================="

# 1. Build & Bundle Flowline.app
if [ ! -d "${APP_BUNDLE}" ] || [ ! -f "${ICON_FILE}" ]; then
    echo "📦 Building application bundle..."
    "${SCRIPT_DIR}/bundle_app.sh"
fi

# 2. Ensure Background Images are Generated
if [ ! -f "${BG_IMAGE}" ] || [ ! -f "${BG_RETINA}" ]; then
    echo "🎨 Generating custom Retina DMG background..."
    python3 "${SCRIPT_DIR}/generate_dmg_background.py"
fi

# 3. Prepare Dist Directory
mkdir -p "${DIST_DIR}"
DMG_PATH="${DIST_DIR}/${DMG_NAME}"
rm -f "${DMG_PATH}"

# Staging directory for building DMG
STAGING_DIR="${BUILD_DIR}/dmg_staging"
rm -rf "${STAGING_DIR}"
mkdir -p "${STAGING_DIR}"

echo "📂 Staging release files..."
cp -R "${APP_BUNDLE}" "${STAGING_DIR}/"

# 4. Build DMG using create-dmg or native hdiutil fallback
if command -v create-dmg >/dev/null 2>&1; then
    echo "🚀 Creating DMG with create-dmg..."
    
    # create-dmg arguments (Brand §06 — 540x400, icon size 120):
    # Flowline.app at (150,210), Applications at (390,210) — matches
    # generate_dmg_background.py art so Finder icons sit on the wells.
    
    CREATE_DMG_ARGS=(
        --volname "${VOL_NAME}"
        --window-pos 200 120
        --window-size 540 400
        --icon-size 120
        --icon "${APP_NAME}.app" 150 210
        --hide-extension "${APP_NAME}.app"
        --app-drop-link 390 210
        --no-internet-enable
    )
    
    if [ -f "${ICON_FILE}" ]; then
        CREATE_DMG_ARGS+=(--volicon "${ICON_FILE}")
    fi
    
    if [ -f "${BG_IMAGE}" ]; then
        CREATE_DMG_ARGS+=(--background "${BG_IMAGE}")
    fi
    
    # Run create-dmg (allowing non-zero exit code if Finder UI scripting has sandbox/warning on headless)
    set +e
    create-dmg "${CREATE_DMG_ARGS[@]}" "${DMG_PATH}" "${STAGING_DIR}"
    STATUS=$?
    set -e
    
    if [ $STATUS -ne 0 ] && [ ! -f "${DMG_PATH}" ]; then
        echo "⚠️  create-dmg encountered an issue, falling back to native hdiutil generator..."
        FALLBACK_NEEDED=true
    else
        FALLBACK_NEEDED=false
    fi
else
    FALLBACK_NEEDED=true
fi

# 5. Native Fallback Generator (hdiutil + custom AppleScript)
if [ "${FALLBACK_NEEDED:-false}" = "true" ]; then
    echo "🛠 Running native hdiutil DMG packaging..."
    
    TMP_DMG="${BUILD_DIR}/tmp_rw.dmg"
    rm -f "${TMP_DMG}"
    
    # Create symlink to /Applications
    ln -s /Applications "${STAGING_DIR}/Applications"
    
    # Copy background into hidden folder
    mkdir -p "${STAGING_DIR}/.background"
    if [ -f "${BG_RETINA}" ]; then
        cp "${BG_RETINA}" "${STAGING_DIR}/.background/background.png"
    elif [ -f "${BG_IMAGE}" ]; then
        cp "${BG_IMAGE}" "${STAGING_DIR}/.background/background.png"
    fi
    
    # Calculate required size in MB + 40MB buffer
    SIZE_KB=$(du -sk "${STAGING_DIR}" | awk '{print $1}')
    SIZE_MB=$(( (SIZE_KB / 1024) + 50 ))
    
    # Create read-write disk image
    hdiutil create -srcfolder "${STAGING_DIR}" -volname "${VOL_NAME}" -fs HFS+ \
        -fsargs "-c c=64,a=16,e=16" -format UDRW -size "${SIZE_MB}m" "${TMP_DMG}"
        
    # Mount RW disk image
    MOUNT_DIR=$(mktemp -d -t flowline_mount)
    DEVICE=$(hdiutil attach -readwrite -noverify -noautoopen "${TMP_DMG}" | grep -E '^/dev/' | head -n 1 | awk '{print $1}')
    MOUNT_POINT=$(hdiutil info | grep "${DEVICE}" | awk '{print $NF}')
    
    # Set volume icon if exists
    if [ -f "${ICON_FILE}" ] && command -v SetFile >/dev/null 2>&1; then
        cp "${ICON_FILE}" "${MOUNT_POINT}/.VolumeIcon.icns"
        SetFile -a C "${MOUNT_POINT}" || true
    fi
    
    # Apply Finder view settings via AppleScript
    echo "✨ Configuring Finder window & icon layout..."
    osascript <<EOF || true
tell application "Finder"
    tell disk "${VOL_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 740, 520}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 120
        set background picture of viewOptions to file ".background:background.png"
        delay 0.5
        set position of item "${APP_NAME}.app" of container window to {150, 210}
        set position of item "Applications" of container window to {390, 210}
        update without registering applications
        delay 0.5
    end tell
end tell
EOF

    # Sync and unmount
    sync || true
    hdiutil detach "${DEVICE}" -force || true
    
    # Convert to compressed, read-only UDZO DMG
    echo "🗜 Compressing release DMG..."
    hdiutil convert "${TMP_DMG}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}"
    rm -f "${TMP_DMG}"
fi

# Clean up staging
rm -rf "${STAGING_DIR}"

# 6. Ad-hoc Sign the DMG
if command -v codesign >/dev/null 2>&1; then
    echo "🔏 Signing DMG image..."
    codesign --force --sign - "${DMG_PATH}" 2>/dev/null || true
fi

# 7. Verification & Summary
if [ -f "${DMG_PATH}" ]; then
    DMG_SIZE=$(du -h "${DMG_PATH}" | awk '{print $1}')
    SHA256=$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')
    
    echo "=================================================="
    echo "🎉 SUCCESS: Release DMG Created!"
    echo "=================================================="
    echo "  📦 Output:   ${DMG_PATH}"
    echo "  📏 Size:     ${DMG_SIZE}"
    echo "  🔐 SHA-256:  ${SHA256}"
    echo "=================================================="
    echo "To test and mount the DMG:"
    echo "  open \"${DMG_PATH}\""
else
    echo "❌ Error: DMG was not created."
    exit 1
fi
