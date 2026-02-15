#!/bin/bash
# build-app.sh — Build FlowDoro.app, generate icon, ad-hoc sign, create DMG, install
set -euo pipefail

APP_NAME="FlowDoro"
BUNDLE_ID="com.tyroneross.flowdoro"
VERSION="1.0"
BUILD_DIR=".build/arm64-apple-macosx/release"
APP_DIR="${APP_NAME}.app"
CONTENTS="${APP_DIR}/Contents"
MACOS="${CONTENTS}/MacOS"
RESOURCES="${CONTENTS}/Resources"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
ENTITLEMENTS="FlowDoro/FlowDoro.entitlements"
PRIVACY_INFO="FlowDoro/PrivacyInfo.xcprivacy"
ICON_SCRIPT="generate-icon.swift"
ICON_OUTPUT="AppIcon.icns"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

step() { echo -e "\n${GREEN}▸ $1${NC}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${NC}"; }
fail() { echo -e "${RED}  ✗ $1${NC}"; exit 1; }

# ─────────────────────────────────────────────
# 1. Build release binary
# ─────────────────────────────────────────────
step "Building ${APP_NAME} (release)..."
swift build -c release 2>&1 | tail -5
BINARY="${BUILD_DIR}/${APP_NAME}"
[ -f "${BINARY}" ] || fail "Build failed — binary not found at ${BINARY}"
echo "  Binary: $(du -h "${BINARY}" | cut -f1) at ${BINARY}"

# ─────────────────────────────────────────────
# 2. Generate app icon
# ─────────────────────────────────────────────
step "Generating app icon..."
if [ -f "${ICON_SCRIPT}" ]; then
    swift "${ICON_SCRIPT}" 2>&1
    if [ -f "${ICON_OUTPUT}" ]; then
        echo "  Icon: $(du -h "${ICON_OUTPUT}" | cut -f1) — ${ICON_OUTPUT}"
    else
        warn "Icon generation produced no output — continuing without icon"
    fi
else
    warn "No ${ICON_SCRIPT} found — continuing without icon"
fi

# ─────────────────────────────────────────────
# 3. Create .app bundle
# ─────────────────────────────────────────────
step "Creating ${APP_DIR} bundle..."
rm -rf "${APP_DIR}"
mkdir -p "${MACOS}" "${RESOURCES}"

# Copy executable
cp "${BINARY}" "${MACOS}/${APP_NAME}"
chmod +x "${MACOS}/${APP_NAME}"

# Copy icon if generated
if [ -f "${ICON_OUTPUT}" ]; then
    cp "${ICON_OUTPUT}" "${RESOURCES}/AppIcon.icns"
fi

# Copy PrivacyInfo if it exists
if [ -f "${PRIVACY_INFO}" ]; then
    cp "${PRIVACY_INFO}" "${RESOURCES}/PrivacyInfo.xcprivacy"
    echo "  Bundled PrivacyInfo.xcprivacy"
fi

# Generate Info.plist
ICON_ENTRY=""
if [ -f "${RESOURCES}/AppIcon.icns" ]; then
    ICON_ENTRY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
fi

cat > "${CONTENTS}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>FlowDoro</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <false/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2026 Tyrone Ross. All rights reserved.</string>
${ICON_ENTRY}
</dict>
</plist>
PLIST

echo "  Info.plist created"
echo "  Bundle structure:"
echo "    ${APP_DIR}/"
echo "      Contents/"
echo "        MacOS/${APP_NAME}"
echo "        Resources/$(ls "${RESOURCES}" | tr '\n' ' ')"
echo "        Info.plist"

# ─────────────────────────────────────────────
# 4. Ad-hoc code signing
# ─────────────────────────────────────────────
step "Code signing (ad-hoc)..."

# Use entitlements if available, but strip sandbox-related ones that need
# a real Developer ID / provisioning profile to work
SIGN_ARGS=(--force --sign - --timestamp=none)

if [ -f "${ENTITLEMENTS}" ]; then
    # Create a local entitlements file without iCloud/Keychain entries
    # (those need a paid developer account + provisioning profile)
    LOCAL_ENT=$(mktemp /tmp/flowdoro-ent.XXXXXX.plist)
    cat > "${LOCAL_ENT}" <<ENT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.network.server</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-only</key>
    <true/>
</dict>
</plist>
ENT
    SIGN_ARGS+=(--entitlements "${LOCAL_ENT}")
    echo "  Using local entitlements (sandbox disabled for ad-hoc build)"
fi

codesign "${SIGN_ARGS[@]}" "${APP_DIR}" 2>&1
echo "  Signed: $(codesign -d -vvv "${APP_DIR}" 2>&1 | grep 'Authority' || echo 'ad-hoc (no authority)')"

# Clean up temp entitlements
[ -n "${LOCAL_ENT:-}" ] && rm -f "${LOCAL_ENT}"

# Verify
codesign --verify --verbose "${APP_DIR}" 2>&1 && echo "  Signature valid" || warn "Signature verification note (ad-hoc is normal)"

# ─────────────────────────────────────────────
# 5. Create DMG installer
# ─────────────────────────────────────────────
step "Creating DMG installer..."
DMG_TEMP=$(mktemp -d /tmp/flowdoro-dmg.XXXXXX)
cp -R "${APP_DIR}" "${DMG_TEMP}/"
ln -s /Applications "${DMG_TEMP}/Applications"

# Remove old DMG if exists
rm -f "${DMG_NAME}"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov \
    -format UDZO \
    "${DMG_NAME}" 2>&1 | tail -2

rm -rf "${DMG_TEMP}"

if [ -f "${DMG_NAME}" ]; then
    echo "  DMG: $(du -h "${DMG_NAME}" | cut -f1) — ${DMG_NAME}"
else
    warn "DMG creation failed — .app bundle is still usable directly"
fi

# ─────────────────────────────────────────────
# 6. Install to /Applications
# ─────────────────────────────────────────────
step "Installing to /Applications..."

# Kill existing instance if running
if pgrep -x "${APP_NAME}" > /dev/null 2>&1; then
    echo "  Stopping running ${APP_NAME}..."
    killall "${APP_NAME}" 2>/dev/null || true
    sleep 1
fi

if cp -R "${APP_DIR}" "/Applications/${APP_DIR}" 2>/dev/null; then
    echo "  Installed to /Applications/${APP_DIR}"
else
    warn "Could not copy to /Applications (may need sudo)."
    echo "  Trying with sudo..."
    sudo cp -R "${APP_DIR}" "/Applications/${APP_DIR}" && echo "  Installed to /Applications/${APP_DIR}" || warn "Install failed — drag from DMG instead"
fi

# Touch to update Spotlight/Launchpad
if [ -d "/Applications/${APP_DIR}" ]; then
    touch "/Applications/${APP_DIR}"
fi

# ─────────────────────────────────────────────
# 7. Clean up build artifacts
# ─────────────────────────────────────────────
step "Cleaning up..."
rm -f "${ICON_OUTPUT}"
rm -rf "AppIcon.iconset"
echo "  Removed temporary icon files"

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ${APP_NAME} v${VERSION} — Build Complete${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "  .app bundle:  ./${APP_DIR}"
[ -f "${DMG_NAME}" ] && echo "  DMG installer: ./${DMG_NAME}"
[ -d "/Applications/${APP_DIR}" ] && echo "  Installed:     /Applications/${APP_DIR}"
echo ""
echo "  Launch:"
echo "    open /Applications/${APP_DIR}"
echo "    — or Spotlight: ⌘+Space → \"FlowDoro\""
echo "    — or Launchpad"
echo ""
echo "  Share:"
[ -f "${DMG_NAME}" ] && echo "    Send ${DMG_NAME} — recipient drags app to Applications"
echo "    (Note: ad-hoc signed — recipient may need to right-click → Open first)"
echo ""
