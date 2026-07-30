//
//  MergedLoaderTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the multi-account merge loader (#17): tagging by account, partial results when
/// an account fails, all-fail behaviour, and cross-account id distinctness.
@MainActor
struct MergedLoaderTests {
    private struct Item: Identifiable, Hashable {
        let id: String
    }

    private struct Boom: Error {}

    private func account(_ label: String) -> Account {
        Account(label: label, token: "t-\(label)")
    }

    @Test func `merges items tagged by their account`() async throws {
        let accA = account("A")
        let accB = account("B")
        let merged = try await MergedLoader.firstPages(accounts: [accA, accB]) { acct in
            acct.id == accA.id ? [Item(id: "1"), Item(id: "2")] : [Item(id: "3")]
        }
        #expect(merged.map(\.item.id) == ["1", "2", "3"])
        #expect(merged.count(where: { $0.account.id == accA.id }) == 2)
        #expect(merged.last?.account.id == accB.id)
    }

    @Test func `a failing account is identified while the others still return`() async {
        let good = account("Good")
        let bad = account("Bad")
        do {
            _ = try await MergedLoader.firstPages(accounts: [bad, good]) { acct in
                if acct.id == bad.id { throw Boom() }
                return [Item(id: "ok")]
            }
            Issue.record("Expected a partial merged page")
        } catch let partial as PartialMergedPage<AccountScoped<Item>> {
            #expect(partial.page.items.map(\.item.id) == ["ok"])
            #expect(partial.page.items.first?.account.id == good.id)
            #expect(partial.failures.map(\.account.id) == [bad.id])
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func `it throws only when every account fails`() async {
        await #expect(throws: Boom.self) {
            _ = try await MergedLoader.firstPages(accounts: [account("A"), account("B")]) { _ -> [Item] in
                throw Boom()
            }
        }
    }

    @Test func `no accounts yields an empty list`() async throws {
        let merged = try await MergedLoader.firstPages(accounts: []) { _ in [Item(id: "x")] }
        #expect(merged.isEmpty)
    }

    @Test func `the same item id in two accounts stays distinct`() async throws {
        let accA = account("A")
        let accB = account("B")
        let merged = try await MergedLoader.firstPages(accounts: [accA, accB]) { _ in [Item(id: "dup")] }
        #expect(merged.count == 2)
        #expect(Set(merged.map(\.id)).count == 2)
    }

    @Test func `merged pages preserve independent account cursors`() async throws {
        let accounts = [account("A"), account("B")]
        let first = try await MergedLoader.page(accounts: accounts, cursor: nil) { account, cursor in
            #expect(cursor == nil)
            return Page(items: [Item(id: "\(account.label)-1")], next: "\(account.label)-next")
        }
        let second = try await MergedLoader.page(accounts: accounts, cursor: first.next) { account, cursor in
            #expect(cursor == "\(account.label)-next")
            return Page(items: [Item(id: "\(account.label)-2")], next: nil)
        }

        #expect(first.items.map(\.item.id) == ["A-1", "B-1"])
        #expect(first.next != nil)
        #expect(second.items.map(\.item.id) == ["A-2", "B-2"])
        #expect(second.next == nil)
    }
}
