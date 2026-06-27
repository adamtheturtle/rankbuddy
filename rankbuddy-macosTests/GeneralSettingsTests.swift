//
//  GeneralSettingsTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

/// Coverage for the general list auto-refresh setting (#69): the human-readable interval
/// label and the off/Duration mapping the timer reads.
struct GeneralSettingsTests {
    @Test func `the interval label reads off below the minimum`() {
        #expect(GeneralSettings.refreshIntervalLabel(0) == "Off")
        #expect(GeneralSettings.refreshIntervalLabel(GeneralSettings.minRefreshSeconds - 1) == "Off")
    }

    @Test func `the interval label formats seconds, whole minutes, and minutes plus seconds`() {
        #expect(GeneralSettings.refreshIntervalLabel(30) == "30s")
        #expect(GeneralSettings.refreshIntervalLabel(120) == "2m")
        #expect(GeneralSettings.refreshIntervalLabel(150) == "2m 30s")
        #expect(GeneralSettings.refreshIntervalLabel(GeneralSettings.maxRefreshSeconds) == "10m")
    }

    @Test func `the interval is nil when off and a duration once at or above the minimum`() {
        #expect(GeneralSettings.refreshInterval(raw: 0) == nil)
        #expect(GeneralSettings.refreshInterval(raw: GeneralSettings.minRefreshSeconds - 1) == nil)
        #expect(GeneralSettings.refreshInterval(raw: 30) == .seconds(30))
        #expect(GeneralSettings.refreshInterval(raw: 90) == .seconds(90))
    }
}
