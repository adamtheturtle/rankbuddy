//
//  ListSortTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

struct ListSortTests {
    private struct Item: Equatable {
        let value: Int?
    }

    @Test func `missing values remain last in both directions`() {
        let items = [Item(value: nil), Item(value: 1), Item(value: 3), Item(value: 2)]
        let forward: (Item, Item) -> Bool = { ($0.value ?? 0) > ($1.value ?? 0) }

        #expect(ListSort.sorted(
            items, reversed: false, isMissing: { $0.value == nil }, by: forward
        ).map(\.value) == [3, 2, 1, nil])
        #expect(ListSort.sorted(
            items, reversed: true, isMissing: { $0.value == nil }, by: forward
        ).map(\.value) == [1, 2, 3, nil])
    }
}
