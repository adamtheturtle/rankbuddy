# Releasing RankBuddy

Direct-download releases are built only from `vMAJOR.MINOR.PATCH` tags.
The release workflow stamps the marketing version from the tag and uses the full Git commit count as its monotonically increasing build number.

## Required GitHub secrets

- `DEVELOPER_ID_APP_CERT_P12_BASE64`: base64-encoded Developer ID Application certificate and private key exported as PKCS#12.
- `DEVELOPER_ID_APP_CERT_PASSWORD`: password protecting that PKCS#12 file.
- `DEVELOPER_ID_PROVISIONING_PROFILE_BASE64`: base64-encoded Developer ID distribution profile for `com.adamdangoor.rankbuddy`, with iCloud key-value store access and the selected signing certificate.
  A registered-Mac development profile cannot be used for this release.
- `ASC_KEY`: base64-encoded App Store Connect API `.p8` key.
- `ASC_KEY_ID`: the API key ID.
- `ASC_ISSUER_ID`: the App Store Connect issuer UUID.
- `SPARKLE_PRIVATE_ED_KEY`: private EdDSA key exported by Sparkle's `generate_keys -x`; used only to sign update enclosures.
- `SPARKLE_PUBLIC_ED_KEY`: matching public EdDSA key.
  The workflow injects it into the tagged Release build as `SUPublicEDKey`.

The workflow deliberately supports only API-key notarization.
Do not add Apple ID/app-specific-password fallback credentials.

## Local release check

Never place credentials in the repository.
Import the Developer ID identity into a local keychain and either store notarization credentials with `notarytool store-credentials`, or export the same `ASC_*` variables used by CI.

```sh
version=1.0.0
build="$(git rev-list --count HEAD)"
scripts/validate-release-version.sh "$version" "$build" "v$version"

scripts/run-xcodebuild.sh ReleaseBuild.log build \
  -quiet \
  -showBuildTimingSummary \
  -project rankbuddy-macos.xcodeproj \
  -scheme rankbuddy-macos \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath DerivedData-Release \
  -resultBundlePath ReleaseBuild.xcresult \
  -onlyUsePackageVersionsFromResolvedFile \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build" \
  CODE_SIGN_IDENTITY=- \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

SIGNING_IDENTITY='Developer ID Application: Name (TEAMID)' \
PROVISIONING_PROFILE=/path/to/RankBuddy-DeveloperID.provisionprofile \
NOTARY_KEYCHAIN_PROFILE=rankbuddy-notary \
scripts/package-and-notarize.sh \
  DerivedData-Release/Build/Products/Release/rankbuddy-macos.app \
  "rankbuddy-v$version.dmg"
```

The packaging script expands Xcode entitlement placeholders and validates the profile's distribution type, expiry, team, application identifier, certificate and restricted entitlements.
It embeds that profile before signing the app, including its team and application identifiers.
It signs nested Sparkle code before the app, signs the DMG, requires accepted notarization, staples the DMG, and checks both the app and DMG with Gatekeeper.

After notarization, `scripts/generate-appcast.sh` downloads the pinned Sparkle tools, signs the DMG enclosure, and publishes `appcast.xml` beside the DMG.
Tagged Release builds read the stable `releases/latest/download/appcast.xml` URL; ordinary Debug builds remain updater-free.
