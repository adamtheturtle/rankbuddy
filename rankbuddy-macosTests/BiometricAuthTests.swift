//
//  BiometricAuthTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

/// Coverage for the biometric-reveal decision (#48). The actual Touch ID prompt can't run in
/// tests, so this pins the pure gate.
@MainActor
struct BiometricAuthTests {
    @Test func `a reveal is challenged only when enabled and biometrics are available`() {
        #expect(BiometricAuth.shouldPrompt(settingEnabled: true, biometricsAvailable: true))
        #expect(!BiometricAuth.shouldPrompt(settingEnabled: false, biometricsAvailable: true))
        #expect(!BiometricAuth.shouldPrompt(settingEnabled: true, biometricsAvailable: false))
        #expect(!BiometricAuth.shouldPrompt(settingEnabled: false, biometricsAvailable: false))
    }
}
