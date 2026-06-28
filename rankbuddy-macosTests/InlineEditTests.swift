//
//  InlineEditTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

struct InlineEditTests {
    @Test func `a changed value commits trimmed`() {
        #expect(InlineEdit.commitValue(original: "Old", edited: "  New Name  ") == "New Name")
    }

    @Test func `an unchanged value does not commit`() {
        #expect(InlineEdit.commitValue(original: "Same", edited: "Same") == nil)
    }

    @Test func `a value differing only by whitespace does not commit`() {
        #expect(InlineEdit.commitValue(original: "Name", edited: "  Name  ") == nil)
    }

    @Test func `an empty or whitespace value does not commit`() {
        #expect(InlineEdit.commitValue(original: "Name", edited: "") == nil)
        #expect(InlineEdit.commitValue(original: "Name", edited: "   ") == nil)
    }
}
