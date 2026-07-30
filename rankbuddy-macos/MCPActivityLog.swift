//
//  MCPActivityLog.swift
//  rankbuddy-macos
//

import Darwin
import Foundation
import MCPKit

/// One recorded MCP tool call (#52).
nonisolated struct MCPActivityEntry: Codable, Identifiable, Hashable {
    let eventID: UUID
    let timestamp: String
    let tool: String
    let detail: String

    var id: UUID {
        eventID
    }

    init(timestamp: String, tool: String, detail: String, eventID: UUID = UUID()) {
        self.eventID = eventID
        self.timestamp = timestamp
        self.tool = tool
        self.detail = detail
    }

    private enum CodingKeys: String, CodingKey {
        case eventID = "event_id"
        case timestamp
        case tool
        case detail
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        eventID = try container.decodeIfPresent(UUID.self, forKey: .eventID) ?? UUID()
        timestamp = try container.decode(String.self, forKey: .timestamp)
        tool = try container.decode(String.self, forKey: .tool)
        detail = try container.decode(String.self, forKey: .detail)
    }
}

/// A cross-process activity log for the MCP server (#52). The `--mcp` subprocess appends a line
/// per tool call (JSONL) to a file in the shared app container; the GUI reads it to show what
/// the server has served. The append/load/clear file I/O is buddy-kit's generic `JSONLLog`
/// (#647); this keeps RankBuddy's entry schema and the pure, unit-tested `parse`.
nonisolated enum MCPActivityLog {
    /// Keep the on-disk log bounded so it can't grow without limit.
    static let maxEntries = 200
    static let maxEncodedEntryBytes = 4096
    private static let maxToolCharacters = 128
    private static let maxDetailCharacters = 512

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
        let entry = boundedEntry(timestamp: stamp, tool: tool, detail: detail)
        _ = withLock(for: url, mode: LOCK_EX) {
            store(for: url).append(entry)
        }
    }

    /// Removes line-breaking/control input and caps a human-readable activity field.
    static func normalizedSummary(_ value: String, maxCharacters: Int) -> String {
        let bounded = value.prefix(maxCharacters + 1)
        let wasTruncated = bounded.count > maxCharacters
        let prefix = String(bounded.prefix(maxCharacters))
        let normalized = prefix
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .map(String.init)
            .joined()
        return wasTruncated ? "\(normalized)…" : normalized
    }

    static func boundedEntry(timestamp: String, tool: String, detail: String) -> MCPActivityEntry {
        let eventID = UUID()
        var tool = normalizedSummary(tool, maxCharacters: maxToolCharacters)
        var detail = normalizedSummary(detail, maxCharacters: maxDetailCharacters)
        var entry = MCPActivityEntry(timestamp: timestamp, tool: tool, detail: detail, eventID: eventID)

        while encodedSize(of: entry) > maxEncodedEntryBytes, !detail.isEmpty {
            detail = String(detail.prefix(detail.count / 2))
            entry = MCPActivityEntry(timestamp: timestamp, tool: tool, detail: detail, eventID: eventID)
        }
        while encodedSize(of: entry) > maxEncodedEntryBytes, !tool.isEmpty {
            tool = String(tool.prefix(tool.count / 2))
            entry = MCPActivityEntry(timestamp: timestamp, tool: tool, detail: detail, eventID: eventID)
        }
        return entry
    }

    private static func encodedSize(of entry: MCPActivityEntry) -> Int {
        (try? JSONEncoder().encode(entry).count) ?? .max
    }

    /// Parses JSONL log contents into entries, skipping any malformed line. Pure.
    static func parse(_ contents: String) -> [MCPActivityEntry] {
        contents.split(separator: "\n").compactMap {
            try? JSONDecoder().decode(MCPActivityEntry.self, from: Data($0.utf8))
        }
    }

    /// The most recent entries, newest first, capped at `limit`.
    static func entries(limit: Int = maxEntries, from url: URL = fileURL) -> [MCPActivityEntry] {
        withLock(for: url, mode: LOCK_EX) {
            let store = store(for: url)
            let entries = Array(store.load().suffix(limit).reversed())
            store.trim()
            return entries
        } ?? []
    }

    /// Clears the log at an exclusive generation boundary. An append that finishes before this
    /// lock is removed; one that acquires its lock afterwards writes the new generation.
    static func clear(_ url: URL = fileURL) {
        _ = withLock(for: url, mode: LOCK_EX) {
            store(for: url).clear()
        }
    }

    /// Coordinates the GUI and every `--mcp` subprocess through a sidecar advisory lock. The
    /// lock file is never removed, so deleting/recreating the JSONL file cannot split lockers
    /// across different inodes. Failure is closed: no file operation runs without coordination.
    private static func withLock<Result>(for url: URL, mode: Int32, operation: () -> Result) -> Result? {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let lockURL = url.appendingPathExtension("lock")
        let descriptor = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { return nil }

        defer {
            _ = flock(descriptor, LOCK_UN)
            _ = close(descriptor)
        }
        guard flock(descriptor, mode) == 0 else { return nil }

        return operation()
    }
}
