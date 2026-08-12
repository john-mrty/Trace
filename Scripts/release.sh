#!/bin/bash
#
# Build, sign, notarize, and publish a Trace release.
#
# Prereqs (one-time):
#   - "Developer ID Application" certificate in the login keychain
#   - notarytool credentials: xcrun notarytool store-credentials trace-notary --apple-id <apple-id>
#
# Usage: Scripts/release.sh <version>   e.g. Scripts/release.sh 1.0
set -euo pipefail

VERSION="${1:?usage: Scripts/release.sh <version>}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$REPO_DIR/.release"
APP="$OUT_DIR/Build/Products/Release/Trace.app"
ZIP="$OUT_DIR/Trace-$VERSION.zip"
PROFILE="trace-notary"

IDENTITY_LINE="$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 || true)"
if [[ -z "$IDENTITY_LINE" ]]; then
  echo "error: no 'Developer ID Application' certificate found (Xcode > Settings > Accounts > Manage Certificates)" >&2
  exit 1
fi
TEAM_ID="$(echo "$IDENTITY_LINE" | sed -E 's/.*\(([A-Z0-9]{10})\)".*/\1/')"
echo "Signing as: $IDENTITY_LINE (team $TEAM_ID)"

xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 || {
  echo "error: notary profile '$PROFILE' missing — run: xcrun notarytool store-credentials $PROFILE --apple-id <apple-id>" >&2
  exit 1
}

echo "==> Building Release..."
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cd "$REPO_DIR/CoreEditor" && yarn install --immutable >/dev/null && yarn build
cd "$REPO_DIR"
xcodebuild -project Trace.xcodeproj -scheme Trace -configuration Release \
  -derivedDataPath "$OUT_DIR" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  MARKETING_VERSION="$VERSION" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build > "$OUT_DIR/xcodebuild.log" 2>&1 || true
grep -E '^\*\* BUILD|error:' "$OUT_DIR/xcodebuild.log" || true
grep -q '\*\* BUILD SUCCEEDED' "$OUT_DIR/xcodebuild.log" || {
  echo "error: build failed — see $OUT_DIR/xcodebuild.log" >&2
  exit 1
}

echo "==> Notarizing..."
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait | tee "$OUT_DIR/notary.log"
grep -q "status: Accepted" "$OUT_DIR/notary.log" || {
  SUBMISSION_ID="$(sed -nE 's/^ *id: ([a-f0-9-]{36})$/\1/p' "$OUT_DIR/notary.log" | head -1)"
  [[ -n "$SUBMISSION_ID" ]] && xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE"
  echo "error: notarization was not accepted" >&2
  exit 1
}

echo "==> Stapling..."
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Verifying (Gatekeeper assessment)..."
spctl -a -vv "$APP"

echo "==> Building DMG..."
DMG="$OUT_DIR/Trace-$VERSION.dmg"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Trace" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"
codesign --sign "Developer ID Application" --timestamp "$DMG"

echo "==> Notarizing DMG..."
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait | tee "$OUT_DIR/notary-dmg.log"
grep -q "status: Accepted" "$OUT_DIR/notary-dmg.log" || {
  SUBMISSION_ID="$(sed -nE 's/^ *id: ([a-f0-9-]{36})$/\1/p' "$OUT_DIR/notary-dmg.log" | head -1)"
  [[ -n "$SUBMISSION_ID" ]] && xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$PROFILE"
  echo "error: DMG notarization was not accepted" >&2
  exit 1
}
xcrun stapler staple "$DMG"

echo "==> Publishing GitHub release v$VERSION..."
gh auth switch --user john-mrty
gh release create "v$VERSION" "$DMG" "$ZIP" --repo john-mrty/Trace \
  --title "Trace $VERSION" --generate-notes || STATUS=$?
gh auth switch --user johnmoriarty-int
exit "${STATUS:-0}"
