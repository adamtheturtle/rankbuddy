# Mac App Store release

RankBuddy has a distinct `RankBuddy-AppStore` target and shared scheme.
It uses the App Store sandbox entitlements and deliberately does not link Sparkle.
Direct-download builds continue to use the `rankbuddy-macos` scheme.

## Required GitHub secrets

- `APPLE_DISTRIBUTION_CERT_P12_BASE64`
- `APPLE_DISTRIBUTION_CERT_PASSWORD`
- `APP_STORE_PROVISIONING_PROFILE_BASE64`
- `APP_STORE_PROVISIONING_PROFILE_NAME`
- `ASC_KEY`, `ASC_KEY_ID`, and `ASC_ISSUER_ID`

The App Store workflow builds the unsigned store product on every push and pull request, then rejects any product containing `Sparkle.framework` or updater symbols.
A manual workflow run with **upload** enabled imports the distribution identity and profile, archives the store scheme, validates the signed archive, and uploads it with the App Store Connect API key.

## App Review

Use the deterministic demo account so review never needs production credentials:

1. Launch RankBuddy.
2. Open Settings → Accounts.
3. Add an account with the token `demo`.
4. Browse Tests, Questions, Interviews, People, and Teams.

The demo uses sanitized in-process fixtures and performs no authenticated network requests.
The `DemoSmokeTests` screenshot methods capture every primary screen in light and dark appearance for store metadata and review.

RankBuddy declares no tracking or collected-data categories in `PrivacyInfo.xcprivacy`.
Its HTTPS traffic uses exempt operating-system cryptography, recorded by `ITSAppUsesNonExemptEncryption=false`.
