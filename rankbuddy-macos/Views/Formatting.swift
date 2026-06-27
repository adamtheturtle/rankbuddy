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

    /// Canonical display names keyed by lower-cased code (and common aliases). A table rather
    /// than a `switch` so the lookup stays a single low-complexity expression.
    private nonisolated static let languageNames: [String: String] = [
        "python": "Python", "python2": "Python 2", "python3": "Python 3",
        "javascript": "JavaScript", "js": "JavaScript",
        "typescript": "TypeScript", "ts": "TypeScript",
        "node": "Node.js", "node.js": "Node.js", "nodejs": "Node.js",
        "swift": "Swift", "go": "Go", "golang": "Go", "rust": "Rust",
        "java": "Java", "kotlin": "Kotlin", "ruby": "Ruby",
        "c": "C", "cpp": "C++", "c++": "C++", "csharp": "C#", "c#": "C#",
        "objective-c": "Objective-C", "objc": "Objective-C",
        "php": "PHP", "html": "HTML", "css": "CSS", "sql": "SQL",
        "mysql": "MySQL", "postgresql": "PostgreSQL", "postgres": "PostgreSQL",
        "bash": "Bash", "shell": "Shell", "sh": "Shell",
        "r": "R", "scala": "Scala", "perl": "Perl", "dart": "Dart"
    ]

    /// A human-friendly name for a language code (e.g. `"cpp"` → `"C++"`, `"python"` →
    /// `"Python"`). Unknown codes are title-cased as a sensible fallback. Mirrors PadBuddy's
    /// normalisation so the same raw API codes read the same across both apps. `nonisolated`
    /// (pure) so off-main callers like `CSVExport` can use it.
    nonisolated static func languageName(_ code: String) -> String {
        if let name = languageNames[code.lowercased()] { return name }

        return code.isEmpty ? code : code.prefix(1).uppercased() + code.dropFirst()
    }

    /// Joins language codes for display, normalising each to its friendly name. Returns nil
    /// when empty so callers can omit the row.
    static func languages(_ codes: [String]?) -> String? {
        guard let codes, !codes.isEmpty else { return nil }

        return codes.map(languageName).formatted(.list(type: .and))
    }
}
