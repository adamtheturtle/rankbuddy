//
//  MCPClientInstallTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

@MainActor
// swiftlint:disable:next type_body_length
struct MCPClientInstallTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "mcp-install.tests.\(UUID().uuidString)") ?? .standard
    }

    @Test func `JSON install preserves existing servers and adds rankbuddy`() throws {
        let url = try temporaryFile(named: "mcp.json")
        try "{\"mcpServers\":{\"other\":{\"command\":\"other\",\"args\":[]}}}".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        try MCPClientInstall.mergeJSONServer(
            into: url,
            client: .cursor,
            command: "/Applications/RankBuddy.app/Contents/MacOS/rankbuddy-macos",
            shouldReplace: { _ in true }
        )

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let servers = try #require(object?["mcpServers"] as? [String: Any])
        let other = try #require(servers["other"] as? [String: Any])
        let rankbuddy = try #require(servers["rankbuddy"] as? [String: Any])

        #expect(other["command"] as? String == "other")
        #expect(rankbuddy["command"] as? String == "/Applications/RankBuddy.app/Contents/MacOS/rankbuddy-macos")
        #expect(rankbuddy["args"] as? [String] == ["--mcp"])
    }

    @Test func `JSON install leaves existing rankbuddy entry untouched when update is cancelled`() throws {
        let url = try temporaryFile(named: "mcp.json")
        try "{\"mcpServers\":{\"rankbuddy\":{\"command\":\"old\",\"args\":[\"--mcp\"]}}}".write(
            to: url,
            atomically: true,
            encoding: .utf8
        )

        try MCPClientInstall.mergeJSONServer(
            into: url,
            client: .claudeDesktop,
            command: "new",
            shouldReplace: { _ in false }
        )

        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let servers = try #require(object?["mcpServers"] as? [String: Any])
        let rankbuddy = try #require(servers["rankbuddy"] as? [String: Any])
        #expect(rankbuddy["command"] as? String == "old")
    }

    @Test func `codex install replaces only rankbuddy table`() throws {
        let url = try temporaryFile(named: "config.toml")
        try """
        [mcp_servers.other]
        command = "other"
        args = []

        [mcp_servers.rankbuddy]
        command = "old"
        args = ["--mcp"]

        [tools]
        enabled = true
        """.write(to: url, atomically: true, encoding: .utf8)

        try MCPClientInstall.upsertCodexServer(
            into: url,
            client: .codex,
            command: "new",
            shouldReplace: { _ in true }
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("[mcp_servers.other]\ncommand = \"other\""))
        #expect(text.contains("[mcp_servers.rankbuddy]\ncommand = \"new\"\nargs = [\"--mcp\"]"))
        #expect(!text.contains("command = \"old\""))
        #expect(text.contains("[tools]\nenabled = true"))
    }

    @Test func `codex install escapes command paths`() throws {
        let url = try temporaryFile(named: "config.toml")

        try MCPClientInstall.upsertCodexServer(
            into: url,
            client: .codex,
            command: #"/tmp/we"ird/rankbuddy-macos"#,
            shouldReplace: { _ in true }
        )

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains(#"command = "/tmp/we\"ird/rankbuddy-macos""#))
    }

    @Test func `JSON install refuses to overwrite a concurrent edit`() throws {
        let url = try temporaryFile(named: "mcp.json")
        try "{}".write(to: url, atomically: true, encoding: .utf8)
        let concurrent = #"{"mcpServers":{"other":{"command":"new"}}}"#

        #expect(throws: MCPClientInstall.ConfigVerificationError.self) {
            try MCPClientInstall.mergeJSONServer(
                into: url,
                client: .cursor,
                command: "rankbuddy",
                shouldReplace: { _ in true },
                beforeWrite: { try concurrent.write(to: url, atomically: true, encoding: .utf8) }
            )
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == concurrent)
    }

    @Test func `codex install refuses to overwrite a concurrent edit`() throws {
        let url = try temporaryFile(named: "config.toml")
        try "".write(to: url, atomically: true, encoding: .utf8)
        let concurrent = "[mcp_servers.other]\ncommand = \"new\"\n"

        #expect(throws: MCPClientInstall.ConfigVerificationError.self) {
            try MCPClientInstall.upsertCodexServer(
                into: url,
                client: .codex,
                command: "rankbuddy",
                shouldReplace: { _ in true },
                beforeWrite: { try concurrent.write(to: url, atomically: true, encoding: .utf8) }
            )
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == concurrent)
    }

    @Test func `JSON install preserves a config symlink`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("shared.json")
        let link = directory.appendingPathComponent("mcp.json")
        try "{}".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try MCPClientInstall.mergeJSONServer(
            into: link,
            client: .cursor,
            command: "rankbuddy",
            shouldReplace: { _ in true }
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        try MCPClientInstall.verifyJSONConfig(at: target, command: "rankbuddy")
    }

    @Test func `codex install preserves a config symlink`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("shared.toml")
        let link = directory.appendingPathComponent("config.toml")
        try "".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try MCPClientInstall.upsertCodexServer(
            into: link,
            client: .codex,
            command: "rankbuddy",
            shouldReplace: { _ in true }
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: link.path)
        #expect(attributes[.type] as? FileAttributeType == .typeSymbolicLink)
        try MCPClientInstall.verifyCodexConfig(at: target, command: "rankbuddy")
    }

    @Test func `codex declaration recognizes quoted and dotted forms`() {
        #expect(MCPClientInstall.codexServerDeclaration(in: "[mcp_servers.\"rankbuddy\"]") == .table)
        #expect(MCPClientInstall.codexServerDeclaration(
            in: #"mcp_servers.rankbuddy = { command = "old" }"#
        ) == .other)
        #expect(MCPClientInstall.codexServerDeclaration(
            in: #"[mcp_servers]"# + "\n" + #"rankbuddy = { command = "old" }"#
        ) == .other)
        #expect(MCPClientInstall.codexServerDeclaration(
            in: #"mcp_servers = { rankbuddy = { command = "old" } }"#
        ) == .other)
        #expect(MCPClientInstall.codexServerDeclaration(in: "[[mcp_servers.rankbuddy]]") == .other)
    }

    @Test func `codex install refuses unsafe existing declaration forms`() throws {
        for declaration in [
            #"mcp_servers.rankbuddy = { command = "old" }"#,
            #"mcp_servers = { rankbuddy = { command = "old" } }"#
        ] {
            let url = try temporaryFile(named: "config.toml")
            try declaration.write(to: url, atomically: true, encoding: .utf8)

            #expect(throws: MCPClientInstall.CodexConfigError.self) {
                try MCPClientInstall.upsertCodexServer(
                    into: url,
                    client: .codex,
                    command: "new",
                    shouldReplace: { _ in true }
                )
            }
            #expect(try String(contentsOf: url, encoding: .utf8) == declaration)
        }
    }

    @Test func `written configs verify the expected server shape`() throws {
        let json = try temporaryFile(named: "mcp.json")
        let toml = try temporaryFile(named: "config.toml")
        let command = "/Applications/RankBuddy.app/Contents/MacOS/rankbuddy-macos"

        try #"{"mcpServers":{"rankbuddy":{"command":"\#(command)","args":["--mcp"]}}}"#.write(
            to: json,
            atomically: true,
            encoding: .utf8
        )
        try MCPClientInstall.codexServerBlock(command: command).write(to: toml, atomically: true, encoding: .utf8)

        try MCPClientInstall.verifyJSONConfig(at: json, command: command)
        try MCPClientInstall.verifyCodexConfig(at: toml, command: command)
    }

    @Test func `parent grant creates and resolves exact missing client folder`() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-config-parent-\(UUID().uuidString)", isDirectory: true)
        let preferred = parent.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let resolved = try MCPClientInstall.configurationFolder(
            granted: parent,
            preferred: preferred,
            fallback: parent
        )

        #expect(resolved == preferred)
        #expect(FileManager.default.fileExists(atPath: preferred.path))
        #expect(!FileManager.default.fileExists(atPath: parent.appendingPathComponent("config.toml").path))
    }

    @Test func `an unrelated granted folder is rejected`() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let preferred = directory.appendingPathComponent(".codex", isDirectory: true)
        let unrelated = directory.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: unrelated, withIntermediateDirectories: false)

        #expect(throws: MCPClientInstall.ConfigVerificationError.self) {
            try MCPClientInstall.configurationFolder(
                granted: unrelated,
                preferred: preferred,
                fallback: directory
            )
        }
        #expect(!FileManager.default.fileExists(atPath: preferred.path))
    }

    @Test func `a moved or missing installed executable requires repair`() throws {
        let defaults = freshDefaults()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let oldCommand = directory.appendingPathComponent("old-rankbuddy")
        let currentCommand = directory.appendingPathComponent("RankBuddy")
        let config = directory.appendingPathComponent("config.toml")
        for url in [oldCommand, currentCommand] {
            _ = FileManager.default.createFile(atPath: url.path, contents: Data())
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        try MCPClientInstall.codexServerBlock(command: currentCommand.path)
            .write(to: config, atomically: true, encoding: .utf8)

        MCPClientInstall.recordInstalledCommand(oldCommand.path, for: .codex, defaults: defaults)
        #expect(MCPClientInstall.needsRepair(
            .codex,
            currentCommand: currentCommand.path,
            defaults: defaults,
            configURL: config
        ))

        MCPClientInstall.recordInstalledCommand(currentCommand.path, for: .codex, defaults: defaults)
        #expect(!MCPClientInstall.needsRepair(
            .codex,
            currentCommand: currentCommand.path,
            defaults: defaults,
            configURL: config
        ))

        try FileManager.default.removeItem(at: currentCommand)
        #expect(MCPClientInstall.needsRepair(
            .codex,
            currentCommand: currentCommand.path,
            defaults: defaults,
            configURL: config
        ))
    }

    @Test func `deleted or edited client configuration requires repair`() throws {
        let defaults = freshDefaults()
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = directory.appendingPathComponent("RankBuddy")
        let config = directory.appendingPathComponent("mcp.json")
        _ = FileManager.default.createFile(atPath: command.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: command.path)
        MCPClientInstall.recordInstalledCommand(command.path, for: .cursor, defaults: defaults)

        let valid = #"{"mcpServers":{"rankbuddy":{"command":"\#(command.path)","args":["--mcp"]}}}"#
        try valid.write(to: config, atomically: true, encoding: .utf8)
        #expect(!MCPClientInstall.needsRepair(
            .cursor, currentCommand: command.path, defaults: defaults, configURL: config
        ))

        try #"{"mcpServers":{"rankbuddy":{"command":"other","args":["--mcp"]}}}"#
            .write(to: config, atomically: true, encoding: .utf8)
        #expect(MCPClientInstall.needsRepair(
            .cursor, currentCommand: command.path, defaults: defaults, configURL: config
        ))

        try FileManager.default.removeItem(at: config)
        #expect(MCPClientInstall.needsRepair(
            .cursor, currentCommand: command.path, defaults: defaults, configURL: config
        ))
    }

    private func temporaryFile(named name: String) throws -> URL {
        try temporaryDirectory().appendingPathComponent(name)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
