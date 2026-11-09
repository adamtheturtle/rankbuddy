//
//  Formatting.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation

nonisolated func uniqueTags(_ tags: [String]?) -> [String] {
    var seen: Set<String> = []
    return (tags ?? []).filter { seen.insert($0).inserted }
}

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

    /// Distinguishes an explicit false value from a field the API did not return.
    static func boolean(
        _ value: Bool?,
        trueLabel: String = "Yes",
        falseLabel: String = "No"
    ) -> String {
        guard let value else { return "Unavailable" }

        return value ? trueLabel : falseLabel
    }

    /// Turns backend enum spellings such as `in_progress` and `company-admin` into localized,
    /// separator-free labels suitable for visible text and VoiceOver.
    nonisolated static func enumLabel(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .map { String($0).localizedCapitalized }
            .joined(separator: " ")
    }

    nonisolated static func enumLabel(_ value: String?) -> String? {
        value.map(enumLabel)
    }

    nonisolated static let hackerRankLanguageOptions: [(code: String, name: String)] = [
        ("bash", "Bash"),
        ("c", "C"),
        ("clojure", "Clojure"),
        ("cpp", "C++"),
        ("cpp14", "C++14"),
        ("cpp17", "C++17"),
        ("cpp20", "C++20"),
        ("cpp23", "C++23"),
        ("csharp", "C#"),
        ("dart", "Dart"),
        ("erlang", "Erlang"),
        ("go", "Go"),
        ("haskell", "Haskell"),
        ("java", "Java"),
        ("java7", "Java 7"),
        ("java8", "Java 8"),
        ("java11", "Java 11"),
        ("java15", "Java 15"),
        ("java17", "Java 17"),
        ("java21", "Java 21"),
        ("javascript", "JavaScript"),
        ("kotlin", "Kotlin"),
        ("objectivec", "Objective-C"),
        ("perl", "Perl"),
        ("php", "PHP"),
        ("python", "Python"),
        ("python2", "Python 2"),
        ("python3", "Python 3"),
        ("r", "R"),
        ("ruby", "Ruby"),
        ("rust", "Rust"),
        ("scala", "Scala"),
        ("swift", "Swift"),
        ("typescript", "TypeScript")
    ]

    private nonisolated static let hackerRankLanguageNames: [String: String] = {
        var names = Dictionary(uniqueKeysWithValues: hackerRankLanguageOptions)
        names["cplusplus"] = "C++"
        names["golang"] = "Go"
        return names
    }()

    /// A human-friendly name for a language code (e.g. `"cpp"` → `"C++"`, `"python"` →
    /// `"Python"`), via buddy-kit's shared `LanguageCatalog` (#640) with fallbacks for HackerRank's
    /// versioned aliases. `nonisolated` (pure) so off-main callers like `CSVExport` can use it.
    nonisolated static func languageName(_ code: String) -> String {
        let key = code.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let compactKey = key
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        if let name = hackerRankLanguageNames[key] ?? hackerRankLanguageNames[compactKey] {
            return name
        }

        for (prefix, name) in [("cplusplus", "C++"), ("cpp", "C++"), ("java", "Java "),
                               ("csharp", "C# "), ("swift", "Swift "), ("kotlin", "Kotlin ")]
            where compactKey.hasPrefix(prefix) {
            let version = compactKey.dropFirst(prefix.count)
            if !version.isEmpty, version.allSatisfy(\.isNumber) {
                return name + version
            }
        }

        return code.languageDisplayName
    }

    /// Joins language codes for display, normalising each to its friendly name. Returns nil
    /// when empty so callers can omit the row.
    static func languages(_ codes: [String]?) -> String? {
        guard let codes, !codes.isEmpty else { return nil }

        return codes.map(languageName).formatted(.list(type: .and))
    }
}
