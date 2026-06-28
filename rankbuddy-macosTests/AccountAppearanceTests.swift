//
//  AccountAppearanceTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import SwiftUI
import Testing

/// Coverage for per-account icon + tint (#64): persistence, the icon default, and hex parsing.
@MainActor
struct AccountAppearanceTests {
    @Test func `icon and tint round-trip and are absent from older saved accounts`() throws {
        let account = Account(label: "Work", token: "t", iconSymbol: "briefcase", tintHex: "#3B82F6")
        let restored = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(account))
        #expect(restored.iconSymbol == "briefcase")
        #expect(restored.tintHex == "#3B82F6")
        #expect(restored == account)

        let legacy = Data(#"{"id":"00000000-0000-0000-0000-000000000001","label":"Old","token":"t"}"#.utf8)
        let old = try JSONDecoder().decode(Account.self, from: legacy)
        #expect(old.iconSymbol == nil)
        #expect(old.tintHex == nil)
    }

    @Test func `displayIcon falls back to the default when unset`() {
        #expect(Account(label: "A", token: "t").displayIcon == Account.defaultIconSymbol)
        #expect(Account(label: "A", token: "t", iconSymbol: "star").displayIcon == "star")
    }

    @Test func `a tint colour is parsed only from a valid hex`() {
        #expect(Account(label: "A", token: "t", tintHex: "#3B82F6").tintColor != nil)
        #expect(Account(label: "A", token: "t", tintHex: "3B82F6").tintColor != nil)
        #expect(Account(label: "A", token: "t").tintColor == nil)
        // Malformed values fall back to the default tint (nil), never crash.
        #expect(Account(label: "A", token: "t", tintHex: "nope").tintColor == nil)
        #expect(Account(label: "A", token: "t", tintHex: "#12").tintColor == nil)
    }

    @Test func `every editor tint preset parses (except the explicit default)`() {
        for tint in AccountAppearance.tints {
            if let hex = tint.hex {
                #expect(Color(accountHex: hex) != nil, "preset \(tint.name) should parse")
            } else {
                #expect(tint.name == "Default")
            }
        }
    }
}
