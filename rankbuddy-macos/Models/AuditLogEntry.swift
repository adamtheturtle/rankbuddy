//
//  AuditLogEntry.swift
//  rankbuddy-macos
//

import Foundation

/// One entry in the organisation's server-side audit log (`GET /audit_log` → `AuditLogShow`):
/// who changed what, when, and from where (#106). Unlike the local Recent Activity (which only
/// records what this app *viewed*), this is the org's actual change history.
///
/// Every field is optional and decoded resiliently so a 2xx response never fails on a shape that
/// varies by `source_type`. `source_id` is accepted as either a string or a number, and `user`
/// as either a bare string or a `{ email, firstname, lastname }` object (via `InterviewPerson`,
/// the shared lenient person decoder).
nonisolated struct AuditLogEntry: Decodable, Hashable, Identifiable {
    /// Identifier of the changed resource.
    let sourceID: String?
    /// The kind of resource changed (e.g. "test", "user", "team").
    let sourceType: String?
    /// A display label for the user who made the change, if known.
    let userLabel: String?
    /// The action performed (e.g. "create", "update", "delete").
    let action: String?
    /// The names of the fields that changed.
    let modifiedFields: [String]
    /// The originating IP address, if recorded.
    let ipAddress: String?
    /// ISO-8601 timestamp of the change.
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case sourceType = "source_type"
        case user
        case action
        case modifiedFields = "modified_fields"
        case ipAddress = "ip_address"
        case createdAt = "created_at"
    }

    /// A stable identity built from the fields that together pin one entry, since the log has no
    /// dedicated id. Good enough to keep rows distinct in a list.
    var id: String {
        "\(sourceType ?? "")-\(sourceID ?? "")-\(action ?? "")-\(createdAt ?? "")"
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = Self.flexibleString(container, .sourceID)
        sourceType = container.lenient(String.self, .sourceType)
        action = container.lenient(String.self, .action)
        modifiedFields = container.lenient([String].self, .modifiedFields) ?? []
        ipAddress = container.lenient(String.self, .ipAddress)
        createdAt = container.lenient(String.self, .createdAt)
        userLabel = container.lenient(InterviewPerson.self, .user)?.displayName
    }

    /// Decodes a key that may arrive as either a JSON string or a number, returning its string
    /// form either way (`source_id` is documented as a string but live records sometimes carry
    /// a numeric id).
    private static func flexibleString(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
        if let string = container.lenient(String.self, key) { return string }
        if let number = container.lenient(Int.self, key) { return String(number) }
        return nil
    }
}

extension AuditLogEntry {
    /// A one-line summary of the change, e.g. "Updated test t1".
    var headline: String {
        let verb = (action ?? "changed").capitalized
        let type = sourceType ?? "record"
        if let sourceID, !sourceID.isEmpty {
            return "\(verb) \(type) \(sourceID)"
        }
        return "\(verb) \(type)"
    }

    /// An SF Symbol name reflecting the action.
    var actionSymbol: String {
        switch action?.lowercased() {
        case "create", "created": "plus.circle"
        case "delete", "deleted", "destroy", "destroyed": "trash"
        case "update", "updated", "edit", "edited": "pencil"
        default: "circle"
        }
    }
}
