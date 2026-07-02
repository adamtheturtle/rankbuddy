//
//  BiometricAuth.swift
//  rankbuddy-macos
//

/// App-side home for the biometric-reveal opt-in key (#48). The LocalAuthentication logic now
/// lives in buddy-kit's `BiometricGate` (#642); only the `@AppStorage` key stays here because it
/// names the app's own defaults domain.
enum BiometricAuth {
    /// `@AppStorage`/`UserDefaults` key for the "require Touch ID to reveal a token" opt-in.
    static let revealSettingKey = "rb.biometricReveal"
}
