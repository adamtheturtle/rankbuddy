//
//  InterviewDetail.swift
//  rankbuddy-macos
//

import Foundation

/// The richer single-interview read (`GET /interviews/{id}` → `InterviewShow`), carrying the
/// fields the list item omits: the scheduled window, the interviewers, the owning user, the
/// candidate, and the links to the résumé and result (#103). Every field is optional so a 2xx
/// detail response never fails to decode on a shape that differs between interview kinds. The
/// collaborative pad's source code is **not** exposed by the API, so it is not modelled here.
nonisolated struct InterviewDetail: Codable, Hashable {
    /// ISO-8601 scheduled start.
    let scheduledFrom: String?
    /// ISO-8601 scheduled end.
    let scheduledTo: String?
    /// URL of the candidate's résumé, if attached.
    let resumeURL: String?
    /// URL of the interview's result/report.
    let resultURL: String?
    /// The people conducting the interview.
    let interviewers: [InterviewPerson]
    /// The interview's owner/creator.
    let user: InterviewPerson?
    /// The candidate being interviewed.
    let candidate: InterviewPerson?

    enum CodingKeys: String, CodingKey {
        case scheduledFrom = "from"
        case scheduledTo = "to"
        case resumeURL = "resume_url"
        case resultURL = "result_url"
        case interviewers
        case user
        case candidate
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scheduledFrom = container.lenient(String.self, .scheduledFrom)
        scheduledTo = container.lenient(String.self, .scheduledTo)
        resumeURL = container.lenient(String.self, .resumeURL)
        resultURL = container.lenient(String.self, .resultURL)
        interviewers = container.lenient([InterviewPerson].self, .interviewers) ?? []
        user = container.lenient(InterviewPerson.self, .user)
        candidate = container.lenient(InterviewPerson.self, .candidate)
    }

    /// Whether the detail carries any people worth a dedicated section, so the UI can avoid an
    /// empty "People" group when the detail response adds nothing over the list row.
    var hasPeople: Bool {
        !interviewers.isEmpty || user != nil || candidate != nil
    }
}

/// A person attached to an interview — an interviewer, the owner, or the candidate. The API
/// returns these either as a bare email/name string or as an object, so this decodes both
/// shapes rather than dropping the field when it differs (#103).
nonisolated struct InterviewPerson: Codable, Hashable {
    let email: String?
    let firstName: String?
    let lastName: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case email
        case firstName = "firstname"
        case lastName = "lastname"
        case name
    }

    init(email: String? = nil, firstName: String? = nil, lastName: String? = nil, name: String? = nil) {
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.name = name
    }

    nonisolated init(from decoder: any Decoder) throws {
        // A bare string (an email address or a display name) is a valid shape for entries in the
        // interviewers array, so decode that before falling back to the keyed object.
        if let single = try? decoder.singleValueContainer(), let value = try? single.decode(String.self) {
            let isEmail = value.contains("@")
            self.init(email: isEmail ? value : nil, name: isEmail ? nil : value)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            email: container.lenient(String.self, .email),
            firstName: container.lenient(String.self, .firstName),
            lastName: container.lenient(String.self, .lastName),
            name: container.lenient(String.self, .name)
        )
    }

    /// A human-readable label: an explicit name, else first + last, else the email, else "Unknown".
    var displayName: String {
        if let name, !name.isEmpty { return name }
        let full = [firstName, lastName]
            .compactMap(\.self)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if !full.isEmpty { return full }
        return email ?? "Unknown"
    }
}

/// The interview's conversation transcript (`GET /interviews/{id}/transcript` →
/// `InterviewTranscriptShow`): the spoken/typed messages only. The collaborative pad's source
/// code is not part of the transcript (#103).
nonisolated struct InterviewTranscript: Codable, Hashable {
    let messages: [InterviewMessage]

    enum CodingKeys: String, CodingKey {
        case messages
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messages = container.lenient([InterviewMessage].self, .messages) ?? []
    }
}

/// One line of an interview transcript (#103). Top-level (not nested in `InterviewTranscript`)
/// so its `CodingKeys` don't exceed the project's type-nesting limit.
nonisolated struct InterviewMessage: Codable, Hashable, Identifiable {
    let messageID: String?
    let author: String?
    let email: String?
    /// Whether the author is the candidate (vs an interviewer), for styling.
    let candidate: Bool?
    /// Unix epoch seconds the message was sent.
    let timestamp: Int?
    let text: String?

    /// Stable identity for `ForEach`: the server's `messageId` when present, otherwise a
    /// composite of the fields that's good enough to keep rows distinct.
    var id: String {
        messageID ?? "\(author ?? "")-\(timestamp ?? 0)-\(text?.count ?? 0)"
    }

    enum CodingKeys: String, CodingKey {
        case messageID = "messageId"
        case author
        case email
        case candidate
        case timestamp
        case text
    }

    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageID = container.lenient(String.self, .messageID)
        author = container.lenient(String.self, .author)
        email = container.lenient(String.self, .email)
        candidate = container.lenient(Bool.self, .candidate)
        timestamp = container.lenient(Int.self, .timestamp)
        text = container.lenient(String.self, .text)
    }
}
