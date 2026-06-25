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

    /// Joins a list for display, returning nil when empty so callers can omit the row.
    static func list(_ values: [String]?) -> String? {
        guard let values, !values.isEmpty else { return nil }

        return values.formatted(.list(type: .and))
    }
}
