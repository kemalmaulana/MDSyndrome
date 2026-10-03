#!/usr/bin/env bash
# Build a universal Release MDSyndrome.app and package it as .zip + .dmg with SHA-256 checksums.
#
#   scripts/package-release.sh <version> [build-number]
#
# Optional, for a trusted (non-Gatekeeper-warning) build:
#   DEVELOPER_ID_APPLICATION  "Developer ID Application: Name (TEAMID)" identity in the keychain
#   NOTARY_APPLE_ID, NOTARY_TEAM_ID, NOTARY_PASSWORD  (app-specific password) → notarize + staple
# Without them the app is ad-hoc signed: it runs, but first launch needs right-click → Open.
set -euo pipefail

VERSION="${1:?usage: package-release.sh <version> [build-number]}"
BUILD="${2:-1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build/Release"
DIST="$ROOT/dist"
APP="$DERIVED/Build/Products/Release/MDSyndrome.app"
NAME="MDSyndrome-$VERSION"

log() { printf '\033[1;35m▸ %s\033[0m\n' "$*"; }

notarize() {
  [[ -n "${NOTARY_APPLE_ID:-}" ]] || return 0
  log "Notarizing $(basename "$1")"
  xcrun notarytool submit "$1" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
    --password "$NOTARY_PASSWORD" --wait
}

cd "$ROOT"
log "Generating Xcode project"
xcodegen generate --quiet

log "Building MDSyndrome $VERSION ($BUILD), Release, universal"
xcodebuild -project MDSyndrome.xcodeproj -scheme MDSyndrome -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$DERIVED" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" ONLY_ACTIVE_ARCH=NO \
  build -quiet

if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  log "Signing with $DEVELOPER_ID_APPLICATION"
  codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$APP"
fi
codesign --verify --strict "$APP"
log "Architectures: $(lipo -archs "$APP/Contents/MacOS/MDSyndrome")"

rm -rf "$DIST"
mkdir -p "$DIST"

# Notarize the app first (via a temporary zip) so the stapled ticket travels inside both packages.
if [[ -n "${NOTARY_APPLE_ID:-}" ]]; then
  ditto -c -k --keepParent "$APP" "$DIST/notarize.zip"
  notarize "$DIST/notarize.zip"
  xcrun stapler staple "$APP"
  rm "$DIST/notarize.zip"
fi

log "Packaging $NAME-macOS.zip"
ditto -c -k --keepParent "$APP" "$DIST/$NAME-macOS.zip"

log "Packaging $NAME.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "MDSyndrome $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$NAME.dmg" >/dev/null
rm -rf "$STAGE"
if [[ -n "${DEVELOPER_ID_APPLICATION:-}" ]]; then
  codesign --force --timestamp --sign "$DEVELOPER_ID_APPLICATION" "$DIST/$NAME.dmg"
fi
if [[ -n "${NOTARY_APPLE_ID:-}" ]]; then
  notarize "$DIST/$NAME.dmg"
  xcrun stapler staple "$DIST/$NAME.dmg"
fi

(cd "$DIST" && shasum -a 256 "$NAME-macOS.zip" "$NAME.dmg" > SHA256SUMS.txt)
log "Done → dist/"
ls -lh "$DIST"
