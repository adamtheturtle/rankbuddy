//
//  MCPClientInstall.swift
//  rankbuddy-macos
//
//  One-click MCP client setup for RankBuddy: write the `rankbuddy` server entry into the
//  selected client's config, preserving any existing servers and leaving copy/paste as a
//  manual fallback.
//

import AppKit
import Foundation

enum MCPClientInstall {
    private static let serverName = "rankbuddy"

    private struct ConfigSpec {
        let preferred: URL?
        let fallback: URL?
        let fileName: String
        let isTOML: Bool
        let message: String
    }

    @MainActor
    static func install(_ client: MCPClient, command: String) {
        let spec = spec(for: client)
        guard let folder = grantFolderAccess(
            preferred: spec.preferred,
            fallback: spec.fallback,
            message: spec.message
        ) else { return }

        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }

        let url = folder.appendingPathComponent(spec.fileName)
        do {
            let didUpdate: (String, String) -> Void = { title, message in
                Task { @MainActor in showAlert(.informational, title, message) }
            }
            if spec.isTOML {
                try upsertCodexServer(
                    into: url,
                    client: client,
                    command: command,
                    shouldReplace: confirmUpdate,
                    didUpdate: didUpdate
                )
            } else {
                try mergeJSONServer(
                    into: url,
                    client: client,
                    command: command,
                    shouldReplace: confirmUpdate,
                    didUpdate: didUpdate
                )
            }
        } catch {
            showAlert(.warning, "Couldn't update \(client.displayName)", error.localizedDescription)
        }
    }

    @MainActor
    private static func spec(for client: MCPClient) -> ConfigSpec {
        let home = realHomeDirectory
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)

        switch client {
        case .claudeDesktop:
            return ConfigSpec(
                preferred: support.appendingPathComponent("Claude", isDirectory: true),
                fallback: support,
                fileName: "claude_desktop_config.json",
                isTOML: false,
                message: "Select Claude Desktop's Claude folder so RankBuddy can add itself."
            )

        case .claudeCode:
            return ConfigSpec(
                preferred: home,
                fallback: home,
                fileName: ".claude.json",
                isTOML: false,
                message: "Select your Home folder so RankBuddy can add itself to ~/.claude.json."
            )

        case .codex:
            return ConfigSpec(
                preferred: home.appendingPathComponent(".codex", isDirectory: true),
                fallback: home,
                fileName: "config.toml",
                isTOML: true,
                message: "Select the .codex folder so RankBuddy can add itself to config.toml."
            )

        case .cursor:
            return ConfigSpec(
                preferred: home.appendingPathComponent(".cursor", isDirectory: true),
                fallback: home,
                fileName: "mcp.json",
                isTOML: false,
                message: "Select the .cursor folder so RankBuddy can add itself to mcp.json."
            )
        }
    }

    static func mergeJSONServer(
        into url: URL,
        client: MCPClient,
        command: String,
        shouldReplace: (MCPClient) -> Bool,
        didUpdate: (String, String) -> Void = { _, _ in }
    ) throws {
        var root = try existingJSON(at: url)
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        let alreadyPresent = servers[serverName] != nil
        if alreadyPresent, !shouldReplace(client) { return }

        servers[serverName] = ["command": command, "args": ["--mcp"]]
        root["mcpServers"] = servers

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)

        let title = alreadyPresent ? "Updated \(client.displayName)" : "Added to \(client.displayName)"
        didUpdate(title, client.restartHint)
    }

    private static func existingJSON(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }

        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }

        return object
    }

    static func upsertCodexServer(
        into url: URL,
        client: MCPClient,
        command: String,
        shouldReplace: (MCPClient) -> Bool,
        didUpdate: (String, String) -> Void = { _, _ in }
    ) throws {
        var text = ""
        if FileManager.default.fileExists(atPath: url.path) {
            text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }

        let block = codexServerBlock(command: command)
        if text.contains("[mcp_servers.\(serverName)]") {
            guard shouldReplace(client) else { return }

            let updated = replacingCodexServer(in: text, with: block)
            try updated.write(to: url, atomically: true, encoding: .utf8)
            didUpdate("Updated \(client.displayName)", client.restartHint)
        } else {
            let merged = text.isEmpty ? block : text + "\n" + block
            try merged.write(to: url, atomically: true, encoding: .utf8)
            didUpdate("Added to \(client.displayName)", client.restartHint)
        }
    }

    static func codexServerBlock(command: String) -> String {
        """
        [mcp_servers.\(serverName)]
        command = "\(command)"
        args = ["--mcp"]

        """
    }

    static func replacingCodexServer(in text: String, with block: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var index = 0

        while index < lines.count {
            if lines[index].trimmingCharacters(in: .whitespaces) == "[mcp_servers.\(serverName)]" {
                result.append(contentsOf: block.components(separatedBy: "\n"))
                index += 1
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("[") {
                    index += 1
                }
            } else {
                result.append(lines[index])
                index += 1
            }
        }

        return result.joined(separator: "\n")
    }

    private static var realHomeDirectory: URL {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    @MainActor
    private static func grantFolderAccess(preferred: URL?, fallback: URL?, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Grant Access"
        panel.message = message
        if let preferred, FileManager.default.fileExists(atPath: preferred.path) {
            panel.directoryURL = preferred
        } else {
            panel.directoryURL = fallback
        }

        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor
    private static func confirmUpdate(_ client: MCPClient) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Update \(client.displayName)?"
        alert.informativeText = "\(client.displayName) already has a rankbuddy server. " +
            "Update it to launch this copy of RankBuddy?"
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    @MainActor
    private static func showAlert(_ style: NSAlert.Style, _ title: String, _ message: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = message
        alert.runModal()
    }
}
