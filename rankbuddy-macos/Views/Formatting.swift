//
//  Formatting.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation

/// Display helpers for the read-only views.
enum DisplayFormat {
    private static let isoWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parses an ISO-8601 timestamp, trying the fractional-seconds then plain internet
    /// formats. Returns nil when the string is missing/empty or can't be parsed.
    static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        return isoWithFractional.date(from: value) ?? iso.date(from: value)
    }

    /// Formats an ISO-8601 timestamp string for display, falling back to the raw string
    /// when it can't be parsed (the API's exact date formats are not all confirmed).
    static func date(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard let parsed = parseDate(value) else { return value }

        return parsed.formatted(date: .abbreviated, time: .shortened)
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// The elapsed time between two ISO-8601 timestamps (e.g. "1h 15m"), or nil when either
    /// is missing/unparseable or the end is not after the start.
    static func duration(fromISO start: String?, toISO end: String?) -> String? {
        guard let start = parseDate(start), let end = parseDate(end), end > start else { return nil }

        return durationFormatter.string(from: end.timeIntervalSince(start))
    }

    private static let intervalFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    /// Formats a raw number of seconds as a short duration (e.g. "1m 30s"), or nil when the
    /// value is missing or non-positive.
    static func interval(_ seconds: Double?) -> String? {
        guard let seconds, seconds > 0 else { return nil }

        return intervalFormatter.string(from: seconds)
    }

    /// Joins a list for display, returning nil when empty so callers can omit the row.
    static func list(_ values: [String]?) -> String? {
        guard let values, !values.isEmpty else { return nil }

        return values.formatted(.list(type: .and))
    }

    /// A human-friendly name for a language code (e.g. `"cpp"` → `"C++"`, `"python"` →
    /// `"Python"`), via buddy-kit's shared `LanguageCatalog` (#640) so the same raw API codes
    /// read identically across RankBuddy and PadBuddy. `nonisolated` (pure) so off-main callers
    /// like `CSVExport` can use it.
    nonisolated static func languageName(_ code: String) -> String {
        code.languageDisplayName
    }

    /// Joins language codes for display, normalising each to its friendly name. Returns nil
    /// when empty so callers can omit the row.
    static func languages(_ codes: [String]?) -> String? {
        guard let codes, !codes.isEmpty else { return nil }

        return codes.map(languageName).formatted(.list(type: .and))
    }
}
