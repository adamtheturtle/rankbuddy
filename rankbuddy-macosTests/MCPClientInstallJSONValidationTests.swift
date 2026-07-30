//
//  MCPClientInstallJSONValidationTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

@MainActor
struct MCPClientInstallJSONValidationTests {
    @Test func `install preserves a non-object mcpServers value on failure`() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-install-json-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("mcp.json")
        let original = Data(#"{"theme":"dark","mcpServers":["future-schema"]}"#.utf8)
        try original.write(to: url)

        #expect(throws: MCPClientInstall.ConfigVerificationError.self) {
            try MCPClientInstall.mergeJSONServer(
                into: url,
                client: .cursor,
                command: "rankbuddy",
                shouldReplace: { _ in true }
            )
        }
        #expect(try Data(contentsOf: url) == original)
    }
}
