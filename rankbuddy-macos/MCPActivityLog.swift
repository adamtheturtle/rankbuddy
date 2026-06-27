//
//  MCPActivityLog.swift
//  rankbuddy-macos
//

import Foundation

/// One recorded MCP tool call (#52).
nonisolated struct MCPActivityEntry: Codable, Identifiable, Hashable {
    let timestamp: String
    let tool: String
    let detail: String

    var id: String {
        "\(timestamp)|\(tool)|\(detail)"
    }
}

/// A cross-process activity log for the MCP server (#52). The `--mcp` subprocess appends a line
/// per tool call (JSONL) to a file in the shared app container; the GUI reads it to show what
/// the server has served. PadBuddy parity (its MCP runs in-process; ours is a separate process,
/// so the shared file is the bridge). The parsing is pure and unit-testable.
nonisolated enum MCPActivityLog {
    /// Keep the on-disk log bounded so it can't grow without limit.
    static let maxEntries = 200

    /// The log file in the app's Application Support container, shared by the GUI and the
    /// `--mcp` subprocess (same sandbox container).
    static var fileURL: URL {
        let directory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.adamdangoor.rankbuddy", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("mcp-activity.jsonl")
    }

    /// Appends a tool call to the log. Called from the `--mcp` subprocess.
    static func record(tool: String, detail: String, to url: URL = fileURL) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = MCPActivityEntry(timestamp: stamp, tool: tool, detail: detail)
        guard let data = try? JSONEncoder().encode(entry),
              let line = String(data: data, encoding: .utf8) else { return }

        let text = line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(text.utf8))
        } else {
            try? Data(text.utf8).write(to: url)
        }
    }

    /// Parses JSONL log contents into entries, skipping any malformed line. Pure.
    static func parse(_ contents: String) -> [MCPActivityEntry] {
        contents.split(separator: "\n").compactMap {
            try? JSONDecoder().decode(MCPActivityEntry.self, from: Data($0.utf8))
        }
    }

    /// The most recent entries, newest first, capped at `limit`.
    static func entries(limit: Int = maxEntries, from url: URL = fileURL) -> [MCPActivityEntry] {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        return parse(contents).suffix(limit).reversed()
    }

    /// Clears the log.
    static func clear(_ url: URL = fileURL) {
        try? FileManager.default.removeItem(at: url)
    }
}
