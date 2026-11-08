//
//  NativeCoverageTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

private struct NativeCoverageManifest: Decodable {
    let operations: [NativeCoverageEntry]
}

private struct NativeCoverageEntry: Decodable {
    let id: String
    let screen: String
    let source: String
    let symbol: String
    let parameters: [String]
    let bodyFields: [String]
    let enumFields: [String: [HackerRankJSONValue]]

    enum CodingKeys: String, CodingKey {
        case id, screen, source, symbol, parameters
        case bodyFields = "body_fields", enumFields = "enum_fields"
    }
}

@MainActor
struct NativeCoverageTests {
    @Test
    func `published operations have an audited native entry point and complete controls`() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONDecoder().decode(NativeCoverageManifest.self,
                                                from: Data(contentsOf: root
                                                    .appending(path: "docs/native-api-coverage.json")))
        let catalogue = try HackerRankClient.apiCatalogue()
        #expect(Set(manifest.operations.map(\.id)) == Set(catalogue.operations.map(\.id)))
        #expect(manifest.operations.count == Set(manifest.operations.map(\.id)).count)
        for entry in manifest.operations {
            #expect(!entry.screen.isEmpty)
            let source = try String(contentsOf: root.appending(path: entry.source), encoding: .utf8)
            #expect(source.contains(entry.symbol), "\(entry.screen) lost its native entry point")
            let form = try NativeFeatureFormModel(operationID: entry.id)
            #expect(Set(form.parameters.map(\.name)) == Set(entry.parameters), "\(entry.id) query/path options changed")
            var controls: [String: NativeFormField] = [:]
            for parameter in form.parameters {
                controls["query." + parameter.name] = parameter
            }
            if let body = form.body {
                for child in body.children {
                    collect(child, path: child.name, into: &controls)
                }
            }
            #expect(Set(controls.keys).isSuperset(of: entry.bodyFields), "\(entry.id) has missing native fields")
            for (path, options) in entry.enumFields {
                #expect(Set(controls[path]?.choices ?? []) == Set(options), "\(entry.id): audit choices for \(path)")
            }
        }
    }

    private func collect(_ field: NativeFormField, path: String, into controls: inout [String: NativeFormField],
                         depth: Int = 0) {
        guard depth < 16 else { return }

        controls[path] = field
        for child in field.children {
            collect(child, path: path + "." + child.name, into: &controls, depth: depth + 1)
        }
        if field.kind == "array" {
            field.addEntry()
            if let item = field.entries.last {
                collect(item, path: path + "[]", into: &controls, depth: depth + 1)
            }
        }
    }
}
