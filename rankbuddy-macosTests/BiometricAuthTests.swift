//
//  BiometricAuthTests.swift
//  rankbuddy-macosTests
//

import BuddyAppKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the biometric-reveal decision (#48/#642). The gate logic now lives in buddy-kit's
/// `BiometricGate`; the actual Touch ID prompt can't run in tests, so this pins the pure gate.
@MainActor
struct BiometricAuthTests {
    @Test func `a reveal is challenged only when enabled and biometrics are available`() {
        #expect(BiometricGate.shouldPrompt(settingEnabled: true, biometricsAvailable: true))
        #expect(!BiometricGate.shouldPrompt(settingEnabled: false, biometricsAvailable: true))
        #expect(!BiometricGate.shouldPrompt(settingEnabled: true, biometricsAvailable: false))
        #expect(!BiometricGate.shouldPrompt(settingEnabled: false, biometricsAvailable: false))
    }
}
