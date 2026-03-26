#!/bin/bash
set -euo pipefail

# Build and package Vigil-ant as a DMG.
#
# Options:
#   --notarize   Enable notarization (requires APPLE_ID and APP_SPECIFIC_PASSWORD env vars)
#
# Team ID is read from ExportOptions.plist.
#
# Usage:
#   ./scripts/build-release.sh              # build + package only
#   ./scripts/build-release.sh --notarize   # build + notarize + package

NOTARIZE=false
for arg in "$@"; do
    case "$arg" in
        --notarize) NOTARIZE=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../Vigilant"
BUILD_DIR="$SCRIPT_DIR/../build"
SCHEME="Vigilant"
ARCHIVE_PATH="$BUILD_DIR/Vigil-ant.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/Vigil-ant.dmg"
EXPORT_OPTIONS="$PROJECT_DIR/ExportOptions.plist"

if [ "$NOTARIZE" = true ]; then
    TEAM_ID=$(/usr/libexec/PlistBuddy -c "Print :teamID" "$EXPORT_OPTIONS")
    for var in APPLE_ID APP_SPECIFIC_PASSWORD; do
        if [ -z "${!var:-}" ]; then
            echo "Error: $var is not set" >&2
            exit 1
        fi
    done
fi

echo "==> Cleaning build directory"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving"
xcodebuild archive \
    -project "$PROJECT_DIR/Vigilant.xcodeproj" \
    -scheme "$SCHEME" \
    -archivePath "$ARCHIVE_PATH" \
    -quiet

if [ "$NOTARIZE" = true ]; then
    echo "==> Exporting (signed)"
    xcodebuild -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportOptionsPlist "$EXPORT_OPTIONS" \
        -exportPath "$EXPORT_PATH" \
        -quiet
else
    echo "==> Extracting app from archive"
    mkdir -p "$EXPORT_PATH"
    cp -R "$ARCHIVE_PATH/Products/Applications/Vigilant.app" "$EXPORT_PATH/"
fi

if [ "$NOTARIZE" = true ]; then
    echo "==> Notarizing"
    ditto -c -k --keepParent "$EXPORT_PATH/Vigilant.app" "$BUILD_DIR/Vigil-ant.zip"

    xcrun notarytool submit "$BUILD_DIR/Vigil-ant.zip" \
        --apple-id "$APPLE_ID" \
        --team-id "$TEAM_ID" \
        --password "$APP_SPECIFIC_PASSWORD" \
        --wait

    echo "==> Stapling"
    xcrun stapler staple "$EXPORT_PATH/Vigilant.app"

    rm -f "$BUILD_DIR/Vigil-ant.zip"
fi

echo "==> Creating DMG"
mkdir -p "$BUILD_DIR/dmg"
cp -R "$EXPORT_PATH/Vigilant.app" "$BUILD_DIR/dmg/"
ln -s /Applications "$BUILD_DIR/dmg/Applications"

hdiutil create -volname "Vigil-ant" \
    -srcfolder "$BUILD_DIR/dmg" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$BUILD_DIR/dmg"

echo "==> Done: $DMG_PATH"
