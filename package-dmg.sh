#!/bin/bash
# Package FlowDoro as a DMG installer with drag-to-Applications
set -euo pipefail

APP_NAME="FlowDoro"
DMG_NAME="${APP_NAME}-Installer"
VERSION="1.0"
VOLUME_NAME="${APP_NAME} ${VERSION}"
DMG_FILE="${DMG_NAME}.dmg"
STAGING_DIR=".dmg-staging"

# Step 1: Build the .app bundle
echo "=== Building ${APP_NAME} ==="
bash "$(dirname "$0")/build-app.sh"

# Step 2: Prepare staging directory
echo ""
echo "=== Preparing DMG contents ==="
rm -rf "${STAGING_DIR}" "${DMG_FILE}"
mkdir -p "${STAGING_DIR}"

# Copy .app bundle
cp -R "${APP_NAME}.app" "${STAGING_DIR}/"

# Create Applications symlink (drag-to-install target)
ln -s /Applications "${STAGING_DIR}/Applications"

# Step 3: Create DMG
echo ""
echo "=== Creating DMG ==="
hdiutil create \
    -volname "${VOLUME_NAME}" \
    -srcfolder "${STAGING_DIR}" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${DMG_FILE}"

# Clean up staging
rm -rf "${STAGING_DIR}"

# Show result
DMG_SIZE=$(du -h "${DMG_FILE}" | cut -f1)
echo ""
echo "=== Done ==="
echo "  ${DMG_FILE} (${DMG_SIZE})"
echo ""
echo "  To install: Open the DMG and drag FlowDoro to Applications"
