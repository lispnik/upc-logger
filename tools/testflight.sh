#!/bin/bash
#
# testflight.sh -- check an App Store .ipa, validate it and upload it.
#
#     make testflight                        # build, then this
#     tools/testflight.sh build/UPC-Logger.ipa
#     tools/testflight.sh --validate build/UPC-Logger.ipa   # upload nothing
#
# doc/testflight.md says where the certificate, the profile and the API key
# come from. Nothing here is secret: the key id and issuer come from the
# environment, and altool reads the .p8 from ~/.appstoreconnect/private_keys.

set -euo pipefail

upload=yes
if [ "${1:-}" = --validate ]; then upload=no; shift; fi
ipa="${1:?usage: $0 [--validate] path/to/app.ipa}"

: "${ASC_KEY_ID:?set ASC_KEY_ID, the App Store Connect API key id}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID, the issuer id the key was made under}"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
unzip -q "$ipa" -d "$work"
app=$(echo "$work"/Payload/*.app)

echo "== checking what was built"
plutil -p "$app/Info.plist" | grep -E 'CFBundleIdentifier|CFBundleVersion|CFBundleShortVersionString|CFBundleIconName'
signature=$(codesign -dvv "$app" 2>&1)
echo "$signature" | grep -E '^Authority=Apple|^TeamIdentifier'
echo "$signature" | grep -q '^Authority=Apple Distribution' \
  || { echo "not signed by an Apple Distribution identity" >&2; exit 1; }
entitlements=$(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -p -)
echo "$entitlements"
if echo "$entitlements" | grep -q '"get-task-allow" => true'; then
  echo "get-task-allow is in the signature; App Store Connect refuses that." >&2
  exit 1
fi
if ! echo "$entitlements" | grep -q 'beta-reports-active'; then
  echo "the profile does not grant beta-reports-active, so this build cannot" >&2
  echo "be tested in TestFlight. Is IOS_DISTRIBUTION_PROFILE an App Store one?" >&2
  exit 1
fi

echo "== validating with App Store Connect"
xcrun altool --validate-app -f "$ipa" -t ios \
             --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

if [ "$upload" = no ]; then
  echo "== validated; not uploading"
  exit 0
fi

echo "== uploading"
xcrun altool --upload-app -f "$ipa" -t ios \
             --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"

echo
echo "Uploaded. App Store Connect takes a few minutes to process it; it then"
echo "appears under TestFlight, and internal testers can install it at once."
