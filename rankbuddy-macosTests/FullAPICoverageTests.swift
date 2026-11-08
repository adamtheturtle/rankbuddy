//
//  FullAPICoverageTests.swift
//  rankbuddy-macosTests
//

import BuddyAppKit
import Foundation
import HackerRankKit
import MCP
@testable import rankbuddy_macos
import Testing

@MainActor
struct FullAPICoverageTests {
    @Test
    func `every documented operation is advertised and runnable in demo mode`() async throws {
        let account = Account(label: "Demo", token: Account.demoToken, scimToken: "provisioning-synthetic-secret")
        let store = AccountStore.rankBuddy(isTesting: true, seed: [account])
        let provider = RankBuddyToolProvider(allowWrites: true, makeStore: { store })
        let catalogue = try HackerRankClient.apiCatalogue()
        let tools = await provider.tools()
        #expect(Set(tools.map(\.name)).count == tools.count)
        #expect(Set(tools.filter { $0.name.hasPrefix("api_") }.map(\.name)) == Set(catalogue.operations.map(\.id)))
        for operation in catalogue.operations {
            var path: [String: Value] = [:]
            var query: [String: Value] = [:]
            for parameter in operation.parameters {
                if parameter.location == "path" {
                    path[parameter.name] = .string("1")
                }
                if parameter.location == "query", parameter.required {
                    query[parameter.name] = .string("1")
                }
            }
            var arguments: [String: Value] = ["path": .object(path), "query": .object(query)]
            if operation.bodyRequired {
                arguments["body"] = .object([:])
            }
            let result = await provider.callTool(operation.id, arguments: arguments)
            #expect(result.isError != true, "\(operation.id) must be runnable")
            for content in result.content {
                if case let .text(text, _, _) = content {
                    #expect(!text.contains("provisioning-synthetic-secret"))
                    #expect(!text.contains("Bearer demo"))
                }
            }
        }
    }

    @Test
    func `write opt-in gates canonical operations even when called directly`() async {
        let store = AccountStore.rankBuddy(isTesting: true, seed: [Account(label: "Demo", token: Account.demoToken)])
        let provider = RankBuddyToolProvider(makeStore: { store })
        let tools = await provider.tools()
        #expect(!tools.contains { $0.name == "api_create_user" })
        #expect(tools.allSatisfy { $0.annotations.readOnlyHint == true })
        let result = await provider.callTool("api_create_user", arguments: ["body": .object([:])])
        #expect(result.isError == true)
    }

    @Test
    func `SCIM credentials persist separately without changing ordinary account identity`() throws {
        let original = Account(label: "Work", token: "v3-synthetic")
        var configured = original
        configured.scimToken = "scim-synthetic"
        let saved = try JSONEncoder().encode(configured)
        let restored = try JSONDecoder().decode(Account.self, from: saved)
        #expect(restored.token == "v3-synthetic")
        #expect(restored.scimToken == "scim-synthetic")
        #expect(!configured.pointsAtDifferentBackend(than: original))
        let old = try JSONDecoder().decode(Account.self, from: JSONEncoder().encode(original))
        #expect(old.scimToken == nil)
    }
}
