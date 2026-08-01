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

// Installer variants share parsing and migration logic in this single namespace.
// swiftlint:disable file_length

// swiftlint:disable:next type_body_length
nonisolated enum MCPClientInstall {
    private static let serverName = "rankbuddy"

    private struct ConfigSpec {
        let preferred: URL?
        let fallback: URL?
        let fileName: String
        let isTOML: Bool
        let message: String
    }

    @MainActor
    static func install(
        _ client: MCPClient,
        command: String,
        didFinish: @escaping @MainActor () -> Void = {}
    ) {
        guard let command = MCPSetup.resolvedCommand(executablePath: command) else {
            showAlert(.warning, "Couldn’t Configure \(client.displayName)", "RankBuddy’s executable is unavailable.")
            return
        }

        let spec = spec(for: client)
        guard let folder = grantFolderAccess(
            preferred: spec.preferred,
            fallback: spec.fallback,
            message: spec.message
        ) else { return }

        Task { @MainActor in
            let accessing = folder.startAccessingSecurityScopedResource()
            defer {
                if accessing { folder.stopAccessingSecurityScopedResource() }
                didFinish()
            }

            do {
                let url = try await runFileOperation {
                    let configFolder = try configurationFolder(
                        granted: folder,
                        preferred: spec.preferred,
                        fallback: spec.fallback
                    )
                    return configFolder.appendingPathComponent(spec.fileName)
                }
                let alreadyPresent = try await runFileOperation {
                    try serverAlreadyPresent(at: url, isTOML: spec.isTOML)
                }
                guard !alreadyPresent || confirmUpdate(client) else { return }

                try await runFileOperation {
                    if spec.isTOML {
                        try upsertCodexServer(
                            into: url, client: client, command: command,
                            shouldReplace: { _ in true }
                        )
                    } else {
                        try mergeJSONServer(
                            into: url, client: client, command: command,
                            shouldReplace: { _ in true }
                        )
                    }
                }
                recordInstalledCommand(command, for: client)
                let title = alreadyPresent ? "Updated \(client.displayName)" : "Added to \(client.displayName)"
                showAlert(.informational, title, client.restartHint)
            } catch {
                showAlert(.warning, "Couldn't update \(client.displayName)", error.localizedDescription)
            }
        }
    }

    nonisolated static func runFileOperation<Result: Sendable>(
        _ operation: @escaping @Sendable () throws -> Result
    ) async throws -> Result {
        try await Task.detached(operation: operation).value
    }

    private nonisolated static func serverAlreadyPresent(at url: URL, isTOML: Bool) throws -> Bool {
        if isTOML {
            guard FileManager.default.fileExists(atPath: url.path) else { return false }

            let text = try String(contentsOf: url, encoding: .utf8)
            return codexServerDeclaration(in: text) != .notDeclared
        }

        let root = try existingJSON(data: existingData(at: url))
        guard let servers = root["mcpServers"] else { return false }
        guard let object = servers as? [String: Any] else {
            throw ConfigVerificationError(
                errorDescription: "The existing “mcpServers” value isn’t a JSON object. No file was changed."
            )
        }

        return object[serverName] != nil
    }

    static func recordInstalledCommand(
        _ command: String,
        for client: MCPClient,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(command, forKey: installedCommandKey(for: client))
    }

    @MainActor
    static func needsRepair(
        _ client: MCPClient,
        currentCommand: String,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        configURL: URL? = nil
    ) -> Bool {
        guard let installed = defaults.string(forKey: installedCommandKey(for: client)) else {
            return false
        }
        guard installed == currentCommand, fileManager.isExecutableFile(atPath: installed) else {
            return true
        }

        let spec = spec(for: client)
        guard let url = configURL ?? spec.preferred?.appendingPathComponent(spec.fileName) else {
            return true
        }

        do {
            if spec.isTOML {
                try verifyCodexConfig(at: url, command: currentCommand)
            } else {
                try verifyJSONConfig(at: url, command: currentCommand)
            }
            return false
        } catch {
            return true
        }
    }

    private static func installedCommandKey(for client: MCPClient) -> String {
        "rb.mcpInstalledCommand.\(client.rawValue)"
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
        beforeWrite: () throws -> Void = {},
        didUpdate: (String, String) -> Void = { _, _ in }
    ) throws {
        let targetURL = try resolvedWriteTarget(for: url)
        try coordinatedWrite(to: targetURL) { coordinatedURL in
            let original = try existingData(at: coordinatedURL)
            var root = try existingJSON(data: original)
            var servers: [String: Any]
            if let existingServers = root["mcpServers"] {
                guard let object = existingServers as? [String: Any] else {
                    throw ConfigVerificationError(
                        errorDescription: "The existing “mcpServers” value isn’t a JSON object. No file was changed."
                    )
                }

                servers = object
            } else {
                servers = [:]
            }
            let alreadyPresent = servers[serverName] != nil
            if alreadyPresent, !shouldReplace(client) { return }

            servers[serverName] = ["command": command, "args": ["--mcp"]]
            root["mcpServers"] = servers

            let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
            try beforeWrite()
            try requireUnchanged(original, at: coordinatedURL)
            try data.write(to: coordinatedURL, options: .atomic)
            try verifyJSONConfig(at: coordinatedURL, command: command)

            let title = alreadyPresent ? "Updated \(client.displayName)" : "Added to \(client.displayName)"
            didUpdate(title, client.restartHint)
        }
    }

    private static func existingJSON(data: Data?) throws -> [String: Any] {
        guard let data, !data.isEmpty else { return [:] }
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
        beforeWrite: () throws -> Void = {},
        didUpdate: (String, String) -> Void = { _, _ in }
    ) throws {
        let targetURL = try resolvedWriteTarget(for: url)
        try coordinatedWrite(to: targetURL) { coordinatedURL in
            let original = try existingData(at: coordinatedURL)
            let text = try original.map { data in
                guard let value = String(data: data, encoding: .utf8) else {
                    throw CocoaError(.fileReadInapplicableStringEncoding)
                }

                return value
            } ?? ""

            let block = codexServerBlock(command: command)
            let updated: String
            let title: String
            switch codexServerDeclaration(in: text) {
            case .notDeclared:
                updated = text.isEmpty ? block : text + "\n" + block
                title = "Added to \(client.displayName)"

            case .table:
                guard shouldReplace(client) else { return }

                updated = replacingCodexServer(in: text, with: block)
                title = "Updated \(client.displayName)"

            case .other:
                throw CodexConfigError(errorDescription:
                    "config.toml already declares the \"rankbuddy\" server in a style " +
                        "RankBuddy can't safely rewrite. " +
                        "Edit its command in config.toml yourself.")
            }

            try beforeWrite()
            try requireUnchanged(original, at: coordinatedURL)
            try updated.write(to: coordinatedURL, atomically: true, encoding: .utf8)
            try verifyCodexConfig(at: coordinatedURL, command: command)
            didUpdate(title, client.restartHint)
        }
    }

    private static func existingData(at url: URL) throws -> Data? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        return try Data(contentsOf: url)
    }

    private static func requireUnchanged(_ original: Data?, at url: URL) throws {
        guard try existingData(at: url) == original else {
            throw ConfigVerificationError(
                errorDescription: "The client config changed while RankBuddy was updating it. " +
                    "No changes were saved; try again."
            )
        }
    }

    private static func coordinatedWrite(to url: URL, body: (URL) throws -> Void) throws {
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var bodyError: Error?
        coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) {
            do {
                try body($0)
            } catch {
                bodyError = error
            }
        }
        if let bodyError { throw bodyError }
        if let coordinationError { throw coordinationError }
    }

    /// Atomic replacement must target a symlink's destination; writing atomically to the link
    /// pathname itself replaces the link. Dangling/cyclic links fail closed.
    static func resolvedWriteTarget(for url: URL, fileManager: FileManager = .default) throws -> URL {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        guard attributes?[.type] as? FileAttributeType == .typeSymbolicLink else { return url }

        let resolved = url.resolvingSymlinksInPath()
        guard resolved.standardizedFileURL != url.standardizedFileURL,
              fileManager.fileExists(atPath: resolved.path)
        else {
            throw ConfigVerificationError(
                errorDescription: "The selected config file is a dangling or cyclic symbolic link."
            )
        }

        return resolved
    }

    static func codexServerBlock(command: String) -> String {
        """
        [mcp_servers.\(serverName)]
        command = \(tomlBasicString(command))
        args = ["--mcp"]
        """
            + "\n"
    }

    static func replacingCodexServer(in text: String, with block: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        var skippingRankBuddyTable = false
        var insertedReplacement = false
        let targetPath = ["mcp_servers", serverName]

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), let path = tomlHeaderKeyPath(line) {
                let belongsToRankBuddy = path.count >= targetPath.count
                    && Array(path.prefix(targetPath.count)) == targetPath
                skippingRankBuddyTable = belongsToRankBuddy
                guard belongsToRankBuddy else {
                    result.append(rawLine)
                    continue
                }

                if path == targetPath, !insertedReplacement, !line.hasPrefix("[[") {
                    result.append(contentsOf: block.components(separatedBy: "\n"))
                    insertedReplacement = true
                }
                continue
            }

            guard !skippingRankBuddyTable else { continue }

            result.append(rawLine)
        }

        return result.joined(separator: "\n")
    }

    static func configurationFolder(
        granted: URL,
        preferred: URL?,
        fallback: URL?,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let preferred, let fallback else {
            throw ConfigVerificationError(errorDescription: "RankBuddy couldn't determine the expected config folder.")
        }

        let grantedPath = granted.resolvingSymlinksInPath().standardizedFileURL
        let preferredPath = preferred.resolvingSymlinksInPath().standardizedFileURL
        let fallbackPath = fallback.resolvingSymlinksInPath().standardizedFileURL
        if grantedPath == preferredPath {
            return granted
        }
        guard grantedPath == fallbackPath,
              preferred.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == fallbackPath,
              !fileManager.fileExists(atPath: preferred.path) else {
            throw ConfigVerificationError(
                errorDescription: "Select the client’s expected config folder: \(preferred.path). No file was changed."
            )
        }

        try fileManager.createDirectory(at: preferred, withIntermediateDirectories: false)
        return preferred
    }

    struct ConfigVerificationError: LocalizedError {
        let errorDescription: String?
    }

    struct CodexConfigError: LocalizedError {
        let errorDescription: String?
    }

    enum CodexDeclaration: Equatable {
        case notDeclared
        case table
        case other
    }

    static func codexServerDeclaration(in text: String) -> CodexDeclaration {
        var currentTable: [String] = []
        var found = CodexDeclaration.notDeclared

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.hasPrefix("[") {
                let isArrayOfTables = line.hasPrefix("[[")
                guard let path = tomlHeaderKeyPath(line) else { continue }

                currentTable = path
                if path == ["mcp_servers", serverName] {
                    return isArrayOfTables ? .other : .table
                }
                if path.count > 2, Array(path.prefix(2)) == ["mcp_servers", serverName] {
                    found = .other
                }
                continue
            }

            guard let keyPath = tomlKeyValueKeyPath(line) else { continue }

            let fullPath = currentTable + keyPath
            if currentTable.isEmpty, keyPath == ["mcp_servers"] {
                return .other
            }
            if fullPath.count >= 2, Array(fullPath.prefix(2)) == ["mcp_servers", serverName] {
                found = .other
            }
        }

        return found
    }

    static func tomlBasicString(_ value: String) -> String {
        var escaped = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\":
                escaped += "\\\\"
            case "\"":
                escaped += "\\\""
            case "\u{08}":
                escaped += "\\b"
            case "\t":
                escaped += "\\t"
            case "\n":
                escaped += "\\n"
            case "\u{0C}":
                escaped += "\\f"
            case "\r":
                escaped += "\\r"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    escaped += String(format: "\\u%04X", scalar.value)
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }
        return "\"\(escaped)\""
    }

    static func verifyJSONConfig(at url: URL, command: String) throws {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let servers = root["mcpServers"] as? [String: Any],
              let rankbuddy = servers[serverName] as? [String: Any],
              rankbuddy["command"] as? String == command,
              rankbuddy["args"] as? [String] == ["--mcp"] else {
            throw ConfigVerificationError(
                errorDescription: "The written JSON configuration did not contain the expected RankBuddy server."
            )
        }
    }

    static func verifyCodexConfig(at url: URL, command: String) throws {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard codexServerDeclaration(in: text) == .table else {
            throw ConfigVerificationError(
                errorDescription: "The written config.toml did not contain a RankBuddy server table."
            )
        }

        let block = codexServerBlock(command: command)
        let rewritten = replacingCodexServer(in: text, with: block)
        guard rewritten == text else {
            throw ConfigVerificationError(
                errorDescription: "The written RankBuddy server table did not preserve its command and arguments."
            )
        }
    }

    private static func tomlHeaderKeyPath(_ line: String) -> [String]? {
        var inner = line
        while inner.hasPrefix("[") {
            inner.removeFirst()
        }
        guard let closing = inner.firstIndex(of: "]") else { return nil }

        inner = String(inner[..<closing])
        return tomlDottedKeyPath(inner)
    }

    private static func tomlKeyValueKeyPath(_ line: String) -> [String]? {
        guard let equals = line.firstIndex(of: "=") else { return nil }

        let key = String(line[..<equals])
        guard !key.isEmpty else { return nil }

        return tomlDottedKeyPath(key)
    }

    private static func tomlDottedKeyPath(_ text: String) -> [String]? {
        var components: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        for character in text {
            if let activeQuote = quote {
                current.append(character)
                if activeQuote == "\"", escaped {
                    escaped = false
                } else if activeQuote == "\"", character == "\\" {
                    escaped = true
                } else if character == activeQuote {
                    quote = nil
                }
            } else if character == "\"" || character == "'" {
                quote = character
                current.append(character)
            } else if character == "." {
                guard !current.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

                components.append(normalizedTOMLKey(current))
                current = ""
            } else {
                current.append(character)
            }
        }

        guard quote == nil, !current.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }

        components.append(normalizedTOMLKey(current))
        return components
    }

    private static func normalizedTOMLKey(_ component: String) -> String {
        var key = component.trimmingCharacters(in: .whitespaces)
        for quote in ["\"", "'"] where key.hasPrefix(quote) && key.hasSuffix(quote) && key.count >= 2 {
            key = String(key.dropFirst().dropLast())
        }
        return key
    }

    static var realHomeDirectory: URL {
        if let passwd = getpwuid(getuid()), let home = passwd.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: home), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    @MainActor
    static func grantFolderAccess(preferred: URL?, fallback: URL?, message: String) -> URL? {
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
