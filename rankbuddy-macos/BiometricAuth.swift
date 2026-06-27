//
//  BiometricAuth.swift
//  rankbuddy-macos
//

import LocalAuthentication

/// Optional biometric (Touch ID) gate for revealing a stored API token in the account editor
/// (#48). Off by default; the user opts in from General settings.
enum BiometricAuth {
    /// `@AppStorage`/`UserDefaults` key for the opt-in.
    static let revealSettingKey = "rb.biometricReveal"

    /// Whether a reveal should be challenged: only when the user enabled it *and* the device
    /// actually has biometrics enrolled. Pure, so it's unit-testable.
    static func shouldPrompt(settingEnabled: Bool, biometricsAvailable: Bool) -> Bool {
        settingEnabled && biometricsAvailable
    }

    /// Whether this device can evaluate biometrics right now.
    static var isBiometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    /// Authenticates before revealing a token. Returns `true` immediately when no prompt is
    /// needed (opt-in off or no biometrics), otherwise the result of the Touch ID prompt.
    @MainActor
    static func authenticateForReveal(reason: String) async -> Bool {
        let enabled = UserDefaults.standard.bool(forKey: revealSettingKey)
        guard shouldPrompt(settingEnabled: enabled, biometricsAvailable: isBiometricsAvailable) else {
            return true
        }

        let context = LAContext()
        return await (try? context.evaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, localizedReason: reason
        )) ?? false
    }

    /// Whether the device can evaluate device-owner authentication (Touch ID *or* password)
    /// right now. Used to gate the *disable* path: turning the reveal requirement off should
    /// itself require auth, but only where the device can actually evaluate it — otherwise a
    /// user with no enrolled biometrics/password would be trapped with the gate stuck on.
    static var canEvaluateOwnerAuth: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Authenticates before *disabling* the reveal gate (#65). Uses `.deviceOwnerAuthentication`
    /// so a password fallback is allowed. Returns `true` (permitting the disable) immediately on
    /// devices that can't evaluate the policy, rather than trapping the user; otherwise returns
    /// the result of the prompt, so a failed or cancelled prompt leaves the gate on.
    @MainActor
    static func authenticateToDisableGate(reason: String) async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }

        return await (try? context.evaluatePolicy(
            .deviceOwnerAuthentication, localizedReason: reason
        )) ?? false
    }
}
