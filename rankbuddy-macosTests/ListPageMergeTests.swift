//
//  ListPageMergeTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

struct ListPageMergeTests {
    private struct Item: Identifiable, Equatable {
        let id: String
        let value: String
    }

    @Test func `overlapping pages update existing rows and append new identities`() {
        let existing = [
            Item(id: "a", value: "old a"),
            Item(id: "b", value: "old b")
        ]
        let incoming = [
            Item(id: "b", value: "new b"),
            Item(id: "c", value: "new c")
        ]

        #expect(ListPageMerge.merge(existing, with: incoming) == [
            Item(id: "a", value: "old a"),
            Item(id: "b", value: "new b"),
            Item(id: "c", value: "new c")
        ])
    }

    @Test func `duplicates within either page collapse to the newest payload`() {
        let merged = ListPageMerge.merge(
            [Item(id: "a", value: "first"), Item(id: "a", value: "second")],
            with: [Item(id: "b", value: "first"), Item(id: "b", value: "second")]
        )

        #expect(merged == [
            Item(id: "a", value: "second"),
            Item(id: "b", value: "second")
        ])
    }
}
