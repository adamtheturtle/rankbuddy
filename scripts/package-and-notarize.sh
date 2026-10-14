#!/usr/bin/env bash

# Developer-ID sign an app inside-out, package it as a DMG, submit it with
# App Store Connect API credentials, staple the ticket, and run end-user checks.
set -euo pipefail

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

app="${1:-}"
dmg="${2:-rankbuddy.dmg}"
[[ -d "$app" ]] || die "usage: $0 <path-to-.app> [output.dmg]"
: "${SIGNING_IDENTITY:?set SIGNING_IDENTITY}"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
entitlements="${ENTITLEMENTS:-$repo_root/rankbuddy-macos/rankbuddy-macos.entitlements}"
[[ -f "$entitlements" ]] || die "entitlements not found: $entitlements"

# SIGNING_IDENTITY_NAME supplies the certificate name when signing by hash.
team_id="$(printf '%s' "${SIGNING_IDENTITY_NAME:-$SIGNING_IDENTITY}" | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p')"
[[ -n "$team_id" ]] || die "could not parse Team ID; set SIGNING_IDENTITY_NAME when signing by hash"
bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"

work="$(mktemp -d)"
cleanup() { rm -rf "$work"; }
trap cleanup EXIT
expanded="$work/app.entitlements"
sed -e "s|\$(PRODUCT_BUNDLE_IDENTIFIER)|$bundle_id|g" \
  -e "s|\$(CFBundleIdentifier)|$bundle_id|g" \
  -e "s|\$(AppIdentifierPrefix)|$team_id.|g" \
  -e "s|\$(TeamIdentifierPrefix)|$team_id.|g" \
  "$entitlements" > "$expanded"

sign() {
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$@"
}

while IFS= read -r -d '' nested; do
  case "$nested" in
    *.xpc | *.app)
      codesign --force --options runtime --timestamp \
        --preserve-metadata=entitlements --sign "$SIGNING_IDENTITY" "$nested"
      ;;
    *) sign "$nested" ;;
  esac
done < <(
  find "$app/Contents" \
    \( -name '*.framework' -o -name '*.dylib' -o -name '*.xpc' -o -name '*.app' -o -name Autoupdate \) \
    -print0 | sort -rz
)
sign --entitlements "$expanded" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

staging="$work/dmg"
mkdir -p "$staging"
cp -R "$app" "$staging/"
ln -s /Applications "$staging/Applications"
hdiutil create -volname RankBuddy -srcfolder "$staging" -fs HFS+ -format UDZO -ov "$dmg"
codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$dmg"

credentials=()
if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  credentials=(--keychain-profile "$NOTARY_KEYCHAIN_PROFILE")
else
  : "${ASC_KEY:?set ASC_KEY or NOTARY_KEYCHAIN_PROFILE}"
  : "${ASC_KEY_ID:?set ASC_KEY_ID}"
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
  key_path="$work/asc-api-key.p8"
  (umask 077; printf '%s' "$ASC_KEY" | base64 --decode > "$key_path")
  credentials=(--key "$key_path" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")
fi

set +e
submission="$(xcrun notarytool submit "$dmg" "${credentials[@]}" --wait 2>&1)"
submission_status=$?
set -e
printf '%s\n' "$submission"
submission_id="$(printf '%s\n' "$submission" | awk '/^[[:space:]]*id:/ { print $2; exit }')"
if (( submission_status != 0 )) || ! grep -q 'status: Accepted' <<< "$submission"; then
  [[ -z "$submission_id" ]] || xcrun notarytool log "$submission_id" "${credentials[@]}" || true
  die "notarization was not accepted"
fi

xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
