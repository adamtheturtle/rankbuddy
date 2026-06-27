//
//  AboutPanelTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

/// Coverage for the About panel's credits (#51). The panel itself is AppKit and can't be
/// asserted headlessly, so this pins the credits content.
struct AboutPanelTests {
    @Test func `the credits describe the app and carry a copyright line`() {
        #expect(AboutPanel.creditsText.contains("HackerRank for Work"))
        #expect(AboutPanel.creditsText.contains("©"))
    }
}
