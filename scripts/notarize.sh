#!/bin/bash
# Build, Developer-ID sign (inside-out), notarize and staple the app.
# Usage: scripts/notarize.sh            # output in ./build/notarize
#        OUT=/some/dir scripts/notarize.sh
# Output: $OUT/<PRODUCT_NAME>.app (stapled) and $OUT/<PRODUCT_NAME>.zip (notarized).
# Needs the Developer ID certificate in the login keychain and the notarytool
# keychain profile named below (created once with `xcrun notarytool store-credentials`).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${OUT:-$ROOT/build/notarize}
TEAM=37G925A9SS
IDENTITY="Developer ID Application: Simone Folador ($TEAM)"
PROFILE=TunnelFlares

cd "$ROOT"

# Preflight: fail before the long build if signing or notarization can't work.
security find-identity -v -p codesigning | grep -qF "$IDENTITY" \
  || { echo "Signing identity not found in keychain: $IDENTITY" >&2; exit 1; }
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || { echo "notarytool keychain profile '$PROFILE' is missing or invalid" >&2; exit 1; }

mkdir -p "$OUT"
xcodegen generate

# project.yml is the source of truth: read the app target's settings from Xcode, not by grep.
SETTINGS=$(xcodebuild -project CCSwitcher.xcodeproj -target CCSwitcher -showBuildSettings 2>/dev/null)
PRODUCT=$(awk '$1=="PRODUCT_NAME"{print $3; exit}' <<<"$SETTINGS")
APP_GROUP_ID=$(awk '$1=="APP_GROUP_ID"{print $3; exit}' <<<"$SETTINGS")
[ -n "$PRODUCT" ] && [ -n "$APP_GROUP_ID" ] || { echo "Could not read PRODUCT_NAME / APP_GROUP_ID from the CCSwitcher target" >&2; exit 1; }

# 1. Build unsigned: Xcode signing would leave get-task-allow on the app.
xcodebuild -project CCSwitcher.xcodeproj -scheme CCSwitcher -configuration Release \
  -derivedDataPath "$OUT/dd" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build | grep -E "error:|BUILD"
BUILT="$OUT/dd/Build/Products/Release/$PRODUCT.app"
[ -d "$BUILT" ] || { echo "Built app not found: $BUILT" >&2; exit 1; }
APP="$OUT/$PRODUCT.app"
rm -rf "$APP"
ditto "$BUILT" "$APP"

# codesign does not expand build settings, so expand $(APP_GROUP_ID) ourselves.
ENT="$OUT/entitlements"
mkdir -p "$ENT"
for f in CCSwitcher/Resources/CCSwitcher.entitlements CCSwitcherWidget/Resources/CCSwitcherWidget.entitlements; do
  sed "s/\$(APP_GROUP_ID)/$APP_GROUP_ID/g" "$f" > "$ENT/$(basename "$f")"
done

# 2. Sign inside-out: widget extension first, then the app.
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  --entitlements "$ENT/CCSwitcherWidget.entitlements" \
  "$APP/Contents/Extensions/CCSwitcherWidgetExtension.appex"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  --entitlements "$ENT/CCSwitcher.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# 3. Zip, notarize, staple, re-zip the stapled app.
ZIP="$OUT/$PRODUCT.zip"
SUBMIT_ZIP="$OUT/$PRODUCT-submit.zip"
rm -f "$ZIP" "$SUBMIT_ZIP"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
SUBMIT_JSON=$(xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$PROFILE" --wait --output-format json)
echo "$SUBMIT_JSON"
if ! grep -q '"status" *: *"Accepted"' <<<"$SUBMIT_JSON"; then
  ID=$(sed -n 's/.*"id" *: *"\([^"]*\)".*/\1/p' <<<"$SUBMIT_JSON" | head -1)
  [ -n "$ID" ] && xcrun notarytool log "$ID" --keychain-profile "$PROFILE" || true
  echo "Notarization failed" >&2
  exit 1
fi
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vvv -t exec "$APP"
ditto -c -k --keepParent "$APP" "$ZIP"
rm -f "$SUBMIT_ZIP"
echo "Notarized: $APP and $ZIP"
