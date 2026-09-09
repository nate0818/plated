#!/bin/bash
# Cut a TestFlight build: bump the build number, archive, export, upload.
#
# The key needs the ADMIN role, and that is the whole reason this script
# works unattended. `xcodebuild -exportArchive` switches to cloud signing the
# moment an authentication key is passed, and an App Manager key is not
# permitted to touch signing certificates: "Cloud signing permission error".
# This script used to sign the export locally to work around that, which was
# fine until the App ID gained a capability. Enabling one invalidates every
# provisioning profile that includes it, Xcode's automatic
# "iOS Team Store Provisioning Profile" included, and regenerating that needs
# an account: without one the export fails with "No Accounts" and a profile
# that "doesn't include the Communication Notifications capability", on a
# machine where nothing is wrong except that nobody is signed in.
#
# So the export takes the key too. An Admin key can cloud sign AND regenerate
# the profile, which means a capability added to the App ID costs nothing
# here: the next build picks it up. Two builds died on this before the key
# was made.
#
# Upload is not distribution. The External group, the one behind the public
# TestFlight link, only holds builds that were added to it, so after the
# upload this waits for processing and adds the build via scripts/asc. Eight
# builds once went up while the link kept serving build 2.
#
# Needs the private key at ~/.appstoreconnect/private_keys/AuthKey_<ID>.p8.
# The two identifiers below are not secrets — useless without that file.
#
# Usage: scripts/testflight.sh [--no-bump] [--archive-only] [--no-distribute]
set -euo pipefail
cd "$(dirname "$0")/.."

# Admin, not App Manager. See the note above: an App Manager key cannot
# cloud sign, so it cannot regenerate a profile the App ID has outgrown.
ASC_KEY_ID="${ASC_KEY_ID:-Y82DF7WZU6}"
ASC_ISSUER_ID="${ASC_ISSUER_ID:-dcfbb9f3-5699-4044-a26a-f3c7c98fbd29}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"

BUMP=1
UPLOAD=1
DISTRIBUTE=1
for arg in "$@"; do
  case "$arg" in
    --no-bump) BUMP=0 ;;
    --archive-only) UPLOAD=0 ;;
    --no-distribute) DISTRIBUTE=0 ;;
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
  echo "▸ build ${current} → ${next}"
else
  next=$current
  echo "▸ build ${next} (unchanged)"
fi

# Same gate as scripts/phone: the widget's copied palette must match.
"$(dirname "${BASH_SOURCE[0]}")/check-tokens" >/dev/null || {
  echo "✗ Design tokens have drifted. Run scripts/check-tokens." >&2; exit 1; }
"$(dirname "${BASH_SOURCE[0]}")/check-design" >/dev/null || {
  echo "✗ A DESIGN.md rule is broken. Run scripts/check-design." >&2; exit 1; }
# A TestFlight build talks to PRODUCTION CloudKit, which does not mint types
# on demand the way Development does. A field the schema has never seen
# fails its save with `.invalidArguments`, and every one of those failures
# in this app is silent: the outbox drops the row after twenty tries with a
# print, and the host of a household simply gets no invite link back. This
# is the one gate whose failure is invisible on the phone, so it is checked
# here rather than remembered. Not applied to `make phone`, which is a Debug
# build against Development and mints as it goes.
"$(dirname "${BASH_SOURCE[0]}")/check-schema" >/dev/null || {
  echo "✗ CloudKit fields are not deployed to Production. Run scripts/check-schema." >&2; exit 1; }

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

echo "▸ exporting (cloud signing with the Admin key — see note at top)…"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist config/ExportOptions.plist \
  -exportPath "$EXPORT" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

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

echo "▸ uploading build ${next}…"
xcrun altool --upload-app --type ios \
  --file "$EXPORT/Plated.ipa" \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID"

if [ "$DISTRIBUTE" = 0 ]; then
  echo "▸ build ${next} uploaded — it reaches Internal after processing (usually 5–15 min)."
  echo "  Add it to External yourself: scripts/asc distribute ${next}"
  exit 0
fi

echo "▸ build ${next} uploaded — waiting for processing, then adding it to External…"
ASC_KEY_ID="$ASC_KEY_ID" ASC_ISSUER_ID="$ASC_ISSUER_ID" ASC_KEY_PATH="$KEY_PATH" \
  "$(dirname "${BASH_SOURCE[0]}")/asc" distribute "${next}" External
