//
//  MergedCollectionTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

/// Coverage for the multi-account merge primitives (#17): the per-row account tagging, the
/// shared "Account" ordering, and `MergedLoader.firstPages`' partial-results contract — one
/// account's failure must not discard the others, but an all-fail must surface an error rather
/// than a misleading empty list.
@MainActor
struct MergedCollectionTests {
    /// A minimal identifiable item so the generic merge logic can be exercised without a model.
    private struct Row: Identifiable, Hashable {
        let id: String
    }

    private struct LoadFailure: Error {}

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

    // MARK: - MergedLoader.firstPages

    @Test func `firstPages tags every item with its source account`() async throws {
        let merged = try await MergedLoader.firstPages(accounts: [work, personal]) { account in
            account.label == "Work" ? [Row(id: "w1"), Row(id: "w2")] : [Row(id: "p1")]
        }
        #expect(merged.count == 3)
        #expect(merged.filter { $0.account == work }.map(\.item.id) == ["w1", "w2"])
        #expect(merged.filter { $0.account == personal }.map(\.item.id) == ["p1"])
    }

    @Test func `firstPages reports the failed account alongside successful rows`() async {
        do {
            _ = try await MergedLoader.firstPages(accounts: [work, personal]) { account in
                if account.label == "Work" {
                    throw LoadFailure()
                }
                return [Row(id: "p1")]
            }
            Issue.record("Expected a partial merged page")
        } catch let partial as PartialMergedPage<AccountScoped<Row>> {
            #expect(partial.page.items.map(\.item.id) == ["p1"])
            #expect(partial.failures.map(\.account.label) == ["Work"])
            #expect(partial.warning.contains("Work"))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func `firstPages throws only when every account fails`() async {
        await #expect(throws: LoadFailure.self) {
            _ = try await MergedLoader.firstPages(accounts: [work, personal]) { _ -> [Row] in
                throw LoadFailure()
            }
        }
    }

    @Test func `firstPages with no accounts is an empty list`() async throws {
        let merged = try await MergedLoader.firstPages(accounts: []) { _ in [Row(id: "x")] }
        #expect(merged.isEmpty)
    }
}
