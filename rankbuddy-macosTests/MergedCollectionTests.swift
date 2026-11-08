//
//  MergedCollectionTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the multi-account merge primitives (#17): the per-row account tagging, the
/// shared "Account" ordering.
@MainActor
struct MergedCollectionTests {
    /// A minimal identifiable item so the generic merge logic can be exercised without a model.
    private struct Row: Identifiable, Hashable {
        let id: String
    }

    private let work = Account(label: "Work", token: "t1")
    private let personal = Account(label: "Personal", token: "t2")

    // MARK: - AccountScoped identity & ordering

    @Test func `the same item id in two accounts stays distinct`() {
        let fromWork = AccountScoped(account: work, item: Row(id: "x"))
        let fromPersonal = AccountScoped(account: personal, item: Row(id: "x"))
        #expect(fromWork.id != fromPersonal.id)
        #expect(fromWork != fromPersonal)
    }

    @Test func `byAccountLabel orders rows by their account label`() {
        let rows = [
            AccountScoped(account: work, item: Row(id: "1")),
            AccountScoped(account: personal, item: Row(id: "2"))
        ]
        let sorted = rows.sorted(by: AccountScoped.byAccountLabel)
        #expect(sorted.map(\.account.label) == ["Personal", "Work"])
    }
}
