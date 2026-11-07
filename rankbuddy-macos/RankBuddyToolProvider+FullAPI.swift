//
//  RankBuddyToolProvider+FullAPI.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit
import MCP
import MCPKit

nonisolated func fullAPIDescriptors(allowWrites: Bool) -> [[String: Any]] {
    guard let catalogue = try? HackerRankClient.apiCatalogue() else { return [] }

    return catalogue.operations.filter { allowWrites || !$0.isWrite }.compactMap { operation in
        guard case var .object(schema) = catalogue.inputSchema(for: operation),
              case var .object(properties)? = schema["properties"] else { return nil }

        properties["account"] = .object(["type": .string("string")])
        schema["properties"] = .object(properties)
        guard let data = try? JSONEncoder().encode(HackerRankJSONValue.object(schema)),
              let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        return [
            "name": operation.id, "description": "\(operation.summary) (\(operation.method) \(operation.path)).",
            "annotations": ["readOnlyHint": !operation.isWrite], "inputSchema": input
        ]
    }
}

nonisolated func fullAPIInputs(_ arguments: [String: Value]?) throws -> HackerRankAPIInputs {
    let values = arguments ?? [:]
    let unknown = Set(values.keys).subtracting(["account", "path", "query", "body"])
    guard unknown.isEmpty else { throw HackerRankError.http(
        0,
        "Unknown argument: \(unknown.sorted().joined(separator: ", "))"
    ) }

    let request = Value.object(values.filter { $0.key != "account" })
    let value = try JSONDecoder().decode(HackerRankJSONValue.self, from: JSONEncoder().encode(request))
    return try HackerRankAPIInputs(value: value)
}

@MainActor
extension RankBuddyToolProvider {
    nonisolated static var writeDescriptors: [[String: Any]] {
        legacyWriteDescriptors + fullAPIDescriptors(allowWrites: true).filter {
            ($0["annotations"] as? [String: Bool])?["readOnlyHint"] == false
        }
    }

    func callFullAPI(_ name: String, arguments: [String: Value]?, account: String?) async -> CallTool.Result {
        do {
            guard let operation = try HackerRankClient.apiCatalogue().operations.first(where: { $0.id == name }) else {
                return errorResult("Unknown tool: \(name)")
            }
            guard allowWrites || !operation.isWrite else { return errorResult("MCP write tools are disabled.") }
            guard let resolved = resolveAccount(account) else { return errorResult("No account configured.") }

            let input = try fullAPIInputs(arguments)
            let client = HackerRankClient(account: resolved)
            let result = try await client.executeAPI(
                name, pathParameters: input.pathParameters, query: input.query, body: input.body,
                scimToken: resolved.scimToken ?? (resolved.isMock ? "demo-scim" : nil)
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(result)
            return CallTool.Result(content: [.text(
                text: String(data: data, encoding: .utf8) ?? "{}",
                annotations: nil,
                _meta: nil
            )])
        } catch let HackerRankError.http(0, message) {
            return errorResult(message)
        } catch {
            return errorResult(rankCoverageError(error))
        }
    }
}

nonisolated func rankCoverageError(_ error: any Error) -> String {
    if let api = error as? HackerRankError {
        switch api {
        case .http(410, _): return "The audit session expired. Refresh to start again."
        case let .http(status, _): return "HackerRank request failed (HTTP \(status))."
        case .missingAPIKey: return "No HackerRank API token configured."
        case .network: return "Could not reach HackerRank."
        case .decode: return "Could not decode the HackerRank response."
        }
    }
    return "The HackerRank request failed."
}
