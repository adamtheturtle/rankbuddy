//
//  BiometricAuthTests.swift
//  rankbuddy-macosTests
//

import BuddyAppKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the biometric-reveal decision (#48/#642). The gate logic now lives in buddy-kit's
/// `BiometricGate`; the actual authentication prompt can't run in tests, so this pins the pure gate.
@MainActor
struct BiometricAuthTests {
    @Test func `a protected reveal stays challenged when biometrics become unavailable`() {
        #expect(BiometricGate.shouldPrompt(settingEnabled: true, biometricsAvailable: true))
        // Protection fails closed and falls back to owner authentication rather than
        // silently revealing the token when Touch ID becomes unavailable.
        #expect(BiometricGate.shouldPrompt(settingEnabled: true, biometricsAvailable: false))
        #expect(!BiometricGate.shouldPrompt(settingEnabled: false, biometricsAvailable: true))
        #expect(!BiometricGate.shouldPrompt(settingEnabled: false, biometricsAvailable: false))
    }
}
