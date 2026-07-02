//
//  MCPActivityLog.swift
//  rankbuddy-macos
//

import Foundation
import MCPKit

/// One recorded MCP tool call (#52).
nonisolated struct MCPActivityEntry: Codable, Identifiable, Hashable, Sendable {
    let timestamp: String
    let tool: String
    let detail: String

    var id: String {
        "\(timestamp)|\(tool)|\(detail)"
    }
}

/// A cross-process activity log for the MCP server (#52). The `--mcp` subprocess appends a line
/// per tool call (JSONL) to a file in the shared app container; the GUI reads it to show what
/// the server has served. The append/load/clear file I/O is buddy-kit's generic `JSONLLog`
/// (#647); this keeps RankBuddy's entry schema and the pure, unit-tested `parse`.
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

    /// The buddy-kit JSONL store backing a given log file, splitting the URL into the directory
    /// and file name the generic store takes.
    private static func store(for url: URL) -> JSONLLog<MCPActivityEntry> {
        JSONLLog(
            directory: url.deletingLastPathComponent(),
            fileName: url.lastPathComponent,
            maxEntries: maxEntries
        )
    }

    /// Appends a tool call to the log. Called from the `--mcp` subprocess.
    static func record(tool: String, detail: String, to url: URL = fileURL) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        store(for: url).append(MCPActivityEntry(timestamp: stamp, tool: tool, detail: detail))
    }

    /// Parses JSONL log contents into entries, skipping any malformed line. Pure.
    static func parse(_ contents: String) -> [MCPActivityEntry] {
        contents.split(separator: "\n").compactMap {
            try? JSONDecoder().decode(MCPActivityEntry.self, from: Data($0.utf8))
        }
    }

    /// The most recent entries, newest first, capped at `limit`.
    static func entries(limit: Int = maxEntries, from url: URL = fileURL) -> [MCPActivityEntry] {
        Array(store(for: url).load().suffix(limit).reversed())
    }

    /// Clears the log.
    static func clear(_ url: URL = fileURL) {
        store(for: url).clear()
    }
}
