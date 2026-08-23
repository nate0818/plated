#!/bin/bash
# Cut a TestFlight build: bump the build number, archive, upload.
#
# App Store Connect authentication comes from an API key you create once at
# App Store Connect › Users and Access › Integrations. Export its identifiers
# and leave the .p8 where Xcode looks for it:
#
#   export ASC_KEY_ID=XXXXXXXXXX
#   export ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
#   # key file at ~/.appstoreconnect/private_keys/AuthKey_$ASC_KEY_ID.p8
#
# Usage: scripts/testflight.sh [--no-bump] [--archive-only]
set -euo pipefail
cd "$(dirname "$0")/.."

BUMP=1
UPLOAD=1
for arg in "$@"; do
  case "$arg" in
    --no-bump) BUMP=0 ;;
    --archive-only) UPLOAD=0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

PROJECT=Plated.xcodeproj
ARCHIVE=build/Plated.xcarchive
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID:-unset}.p8}"

# The app and its widget extension must carry the same build number — App
# Store Connect rejects a mismatch — so every config gets bumped together.
current=$(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9]*' "$PROJECT/project.pbxproj" | grep -o '[0-9]*')
if [ "$BUMP" = 1 ]; then
  next=$((current + 1))
  sed -i '' "s/CURRENT_PROJECT_VERSION = $current;/CURRENT_PROJECT_VERSION = $next;/g" "$PROJECT/project.pbxproj"
  echo "▸ build $current → $next"
else
  next=$current
  echo "▸ build $next (unchanged)"
fi

rm -rf "$ARCHIVE"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme Plated \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates

if [ "$UPLOAD" = 0 ]; then
  echo "▸ archived at $ARCHIVE (upload skipped)"
  exit 0
fi

if [ -z "${ASC_KEY_ID:-}" ] || [ -z "${ASC_ISSUER_ID:-}" ] || [ ! -f "$KEY_PATH" ]; then
  echo "▸ archived at $ARCHIVE" >&2
  echo "No App Store Connect API key configured — set ASC_KEY_ID and ASC_ISSUER_ID" >&2
  echo "with the key at $KEY_PATH, or upload from Xcode's Organizer." >&2
  exit 1
fi

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist config/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

echo "▸ build $next uploaded — it appears in TestFlight after processing (usually 5–15 min)"
