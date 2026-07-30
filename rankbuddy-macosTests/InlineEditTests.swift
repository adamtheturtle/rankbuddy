//
//  InlineEditTests.swift
//  rankbuddy-macosTests
//

import BuddyDesignSystem
@testable import rankbuddy_macos
import Testing

struct InlineEditTests {
    @Test func `inline edit button appears before accepting focus or clicks`() {
        #expect(!InlineEditButtonVisibility.shows(isHovered: false, isFocused: false))
        #expect(InlineEditButtonVisibility.shows(isHovered: true, isFocused: false))
        #expect(InlineEditButtonVisibility.shows(isHovered: false, isFocused: true))
    }

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

    @Test func `inline rename detects a refreshed underlying title`() {
        #expect(!CommandEditableTitle.hasConflict(original: "Original", current: "Original"))
        #expect(CommandEditableTitle.hasConflict(original: "Original", current: "Renamed elsewhere"))
    }

    @Test func `inline text detects refreshed server content`() {
        #expect(!InlineEditableText.hasConflict(original: "Original", current: "Original"))
        #expect(InlineEditableText.hasConflict(original: "Original", current: "Changed elsewhere"))
    }
}
