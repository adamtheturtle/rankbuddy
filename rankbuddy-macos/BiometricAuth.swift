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
}
