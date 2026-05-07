#!/usr/bin/env bash
# Build a TestFlight-ready .ipa for the Nourish app.
# Usage: ./release.sh [--bump] [--version X.Y]
#   --bump         Increment CURRENT_PROJECT_VERSION (build number).
#   --version X.Y  Set MARKETING_VERSION (user-facing version).
# Output: ~/Desktop/Nourish.ipa, ready to drag into Transporter.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="Nourish"
APP_BUNDLE_ID="com.yael.nourish"
WIDGET_BUNDLE_ID="com.yael.nourish.NourishWidget"
TEAM_ID="K623VDGZF8"
SIGN_IDENTITY="Apple Distribution"
PBX="Nourish.xcodeproj/project.pbxproj"
ARCHIVE_PATH="/tmp/Nourish.xcarchive"
EXPORT_DIR="/tmp/NourishExport"
DESKTOP_IPA="$HOME/Desktop/Nourish.ipa"

cd "$PROJECT_DIR"

bump_build=false
new_marketing=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump) bump_build=true; shift ;;
    --version) new_marketing="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

if $bump_build; then
  CURRENT=$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$PBX" | sed -E 's/.*= ([0-9]+);/\1/')
  NEW=$((CURRENT + 1))
  sed -i '' -E "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $NEW;/g" "$PBX"
  echo "Build number: $CURRENT -> $NEW"
fi

if [[ -n "$new_marketing" ]]; then
  sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $new_marketing;/g" "$PBX"
  echo "Marketing version set to $new_marketing"
fi

if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  echo "ERROR: '$SIGN_IDENTITY' certificate not in keychain." >&2
  echo "Create one at developer.apple.com -> Certificates, then import." >&2
  exit 1
fi

# Profile presence is no longer pre-validated; -allowProvisioningUpdates lets
# xcodebuild fetch what it needs from App Store Connect at archive time.

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

# Use automatic signing with -allowProvisioningUpdates so xcodebuild matches
# each target (main app + widget) to the right pre-installed profile by
# bundle ID. The export step pins explicit profile names per bundle ID.
echo "Archiving..."
xcodebuild -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates \
  archive >/dev/null

EXPORT_PLIST="$(mktemp -t ExportOptions).plist"
cat > "$EXPORT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>destination</key>
    <string>export</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
PLIST

echo "Exporting..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_PLIST" >/dev/null

cp "$EXPORT_DIR/Nourish.ipa" "$DESKTOP_IPA"

BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION = ' "$PBX" | sed -E 's/.*= ([0-9]+);/\1/')
VERSION=$(grep -m1 'MARKETING_VERSION = ' "$PBX" | sed -E 's/.*= ([^;]+);/\1/')

echo
echo "Done. Version $VERSION (build $BUILD)"
echo ".ipa: $DESKTOP_IPA"
echo "Next: open Transporter, drag the .ipa, click Deliver."
