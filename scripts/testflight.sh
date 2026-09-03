#!/bin/bash
# Cut a TestFlight build: bump the build number, archive, export, upload.
#
# Two steps rather than one on purpose. `xcodebuild -exportArchive` switches
# to cloud signing the moment an authentication key is passed, and a key with
# the App Manager role is not permitted to touch signing certificates —
# "Cloud signing permission error / No signing certificate iOS Distribution
# found". So the export signs locally with the Apple Distribution certificate
# in the keychain, and altool does the upload, which App Manager may do.
#
# Needs the private key at ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8.
# The two identifiers below are not secrets — useless without that file.
#
# Usage: scripts/testflight.sh [--no-bump] [--archive-only]
set -euo pipefail
cd "$(dirname "$0")/.."

ASC_KEY_ID="${ASC_KEY_ID:-PHQC2AV3TY}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-dcfbb9f3-5699-4044-a26a-f3c7c98fbd29}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

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
EXPORT=build/export

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

# Same gate as scripts/phone: the widget's copied palette must match.
"$(dirname "${BASH_SOURCE[0]}")/check-tokens" >/dev/null || {
  echo "✗ Design tokens have drifted. Run scripts/check-tokens." >&2; exit 1; }
"$(dirname "${BASH_SOURCE[0]}")/check-design" >/dev/null || {
  echo "✗ A DESIGN.md rule is broken. Run scripts/check-design." >&2; exit 1; }

rm -rf "$ARCHIVE" "$EXPORT"
echo "▸ archiving…"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme Plated \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates \
  -quiet

echo "▸ exporting (signed locally, no auth key — see note at top)…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist config/ExportOptions.plist \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates

if [ "$UPLOAD" = 0 ]; then
  echo "▸ exported to $EXPORT/Plated.ipa (upload skipped)"
  exit 0
fi

if [ ! -f "$KEY_PATH" ]; then
  echo "▸ exported to $EXPORT/Plated.ipa" >&2
  echo "No API key at $KEY_PATH — upload skipped." >&2
  echo "Download it from App Store Connect › Users and Access › Integrations." >&2
  exit 1
fi

echo "▸ uploading build $next…"
xcrun altool --upload-app --type ios \
  --file "$EXPORT/Plated.ipa" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

echo "▸ build $next uploaded — it reaches TestFlight after processing (usually 5–15 min)"
