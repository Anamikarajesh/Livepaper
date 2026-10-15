#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LivePaper"
DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
DMG_ROOT="${DIST_DIR}/dmg-root"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

bash scripts/package_app.sh

VERSION="$("${PLIST_BUDDY}" -c "Print :CFBundleShortVersionString" "${APP_DIR}/Contents/Info.plist")"
DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}-macOS.dmg"

rm -rf "${DMG_ROOT}" "${DMG_PATH}"
mkdir -p "${DMG_ROOT}"

cp -R "${APP_DIR}" "${DMG_ROOT}/${APP_NAME}.app"
ln -s /Applications "${DMG_ROOT}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_ROOT}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}" >/dev/null

rm -rf "${DMG_ROOT}"

echo "Created ${DMG_PATH}"
