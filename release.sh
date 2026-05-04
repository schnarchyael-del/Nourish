#!/usr/bin/env bash
# Build a TestFlight-ready .ipa for the Nourish app.
# Usage: ./release.sh [--bump] [--version X.Y]
#   --bump         Increment CURRENT_PROJECT_VERSION (build number).
#   --version X.Y  Set MARKETING_VERSION (user-facing version).
# Output: ~/Desktop/Nourish.ipa, ready to drag into Transporter.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="Nourish"
BUNDLE_ID="com.yael.nourish"
TEAM_ID="K623VDGZF8"
SIGN_IDENTITY="Apple Distribution"
PROFILE_NAME="Nourish App Store"
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

profile_found=false
for dir in "$HOME/Library/MobileDevice/Provisioning Profiles" \
           "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do
  [[ -d "$dir" ]] || continue
  for p in "$dir"/*.mobileprovision; do
    [[ -e "$p" ]] || continue
    if security cms -D -i "$p" 2>/dev/null | grep -q "<string>$PROFILE_NAME</string>"; then
      profile_found=true
      break 2
    fi
  done
done
if ! $profile_found; then
  echo "ERROR: Provisioning profile '$PROFILE_NAME' not installed." >&2
  echo "Download from developer.apple.com -> Profiles, then double-click." >&2
  exit 1
fi

rm -rf "$ARCHIVE_PATH" "$EXPORT_DIR"

echo "Archiving..."
xcodebuild -scheme "$SCHEME" -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  PROVISIONING_PROFILE_SPECIFIER="$PROFILE_NAME" \
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
    <string>manual</string>
    <key>signingCertificate</key>
    <string>$SIGN_IDENTITY</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>$BUNDLE_ID</key>
        <string>$PROFILE_NAME</string>
    </dict>
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
