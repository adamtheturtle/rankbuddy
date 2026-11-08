//
//  Templates.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

nonisolated enum TemplateKind: String, CaseIterable, Identifiable, Codable {
    case interview
    case invitation

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .interview: "Interview Templates"
        case .invitation: "Invitation Email Templates"
        }
    }
}

nonisolated enum TemplateOwnership: String, CaseIterable, Identifiable {
    case all
    case owned
    case shared

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .all: "All Templates"
        case .owned: "Owned by Me"
        case .shared: "Shared with Me"
        }
    }

    var apiFilter: InterviewTemplateFilter? {
        switch self {
        case .all: nil
        case .owned: .owned
        case .shared: .shared
        }
    }
}

/// A cacheable display record, without credentials. Missing API identifiers still get a row.
nonisolated struct TemplateRecord: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let apiID: String?
    let kind: TemplateKind
    let title: String
    let createdAt: String?
    let updatedAt: String?
    let owner: String?
    let status: Int?
    let roles: [String]?
    let questionIDs: [String]?
    let scorecard: Int?
    let editorAccess: Bool?
    let importTemplate: Bool?
    let subject: String?
    let content: String?
    let isDefault: Bool?

    init(interview: InterviewTemplate) {
        apiID = interview.id.map(String.init)
        id = "interview:\(apiID ?? UUID().uuidString)"
        kind = .interview
        title = Self.nonBlank(interview.name)
            ?? apiID.map { "Interview Template \($0)" }
            ?? "Unnamed Interview Template"
        createdAt = interview.createdAt
        updatedAt = nil
        owner = interview.user.map(String.init)
        status = interview.status
        roles = interview.roles
        questionIDs = interview.questions
        scorecard = interview.scorecard
        editorAccess = interview.editorAccess
        importTemplate = interview.importTemplate
        subject = nil
        content = nil
        isDefault = nil
    }

    init(invitation: InviteTemplate) {
        apiID = Self.nonBlank(invitation.id)
        id = "invitation:\(apiID ?? UUID().uuidString)"
        kind = .invitation
        title = Self.nonBlank(invitation.name) ?? apiID.map { "Email Template \($0)" } ?? "Unnamed Email Template"
        createdAt = invitation.createdAt
        updatedAt = invitation.updatedAt
        owner = invitation.user
        status = nil
        roles = nil
        questionIDs = nil
        scorecard = nil
        editorAccess = nil
        importTemplate = nil
        subject = invitation.subject
        content = invitation.content
        isDefault = invitation.isDefault
    }

    var subtitle: String? {
        switch kind {
        case .interview:
            questionIDs.map { "\($0.count) \($0.count == 1 ? "question" : "questions")" }
        case .invitation:
            isDefault == true ? "Default invitation email" : subject
        }
    }

    var searchableText: String {
        [title, apiID, subject, owner, roles?.joined(separator: " ")].compactMap(\.self).joined(separator: " ")
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}

enum TemplateLibrary {
    nonisolated static func cacheKey(accountID: UUID, kind: TemplateKind, ownership: TemplateOwnership) -> String {
        let scope = kind == .interview ? ownership.rawValue : TemplateOwnership.all.rawValue
        return "selection.templates.\(kind.rawValue).\(scope).\(accountID)"
    }

    static func page(
        client: HackerRankClient,
        kind: TemplateKind,
        ownership: TemplateOwnership,
        cursor: String?,
        query: [URLQueryItem] = []
    ) async throws -> Page<TemplateRecord> {
        switch kind {
        case .interview:
            let page = try await NativeListQuery.page(
                InterviewTemplate.self, client: client, operationID: "api_list_all_interview_templates",
                query: query.filter { $0.name != "filter" } + (ownership.apiFilter.map {
                    [URLQueryItem(name: "filter", value: $0.rawValue)]
                } ?? []), cursor: cursor
            )
            return Page(
                items: page.items.map { TemplateRecord(interview: $0) },
                next: page.next,
                totalCount: page.totalCount
            )

        case .invitation:
            let page = try await NativeListQuery.page(
                InviteTemplate.self, client: client, operationID: "api_list_all_invite_templates", query: query,
                cursor: cursor
            )
            return Page(
                items: page.items.map { TemplateRecord(invitation: $0) },
                next: page.next,
                totalCount: page.totalCount
            )
        }
    }

    static func detail(_ record: TemplateRecord, client: HackerRankClient) async throws -> TemplateRecord {
        guard let id = record.apiID else { return record }

        switch record.kind {
        case .interview:
            guard let numericID = Int(id) else { return record }

            return try await TemplateRecord(interview: client.interviewTemplate(id: numericID))

        case .invitation:
            return try await TemplateRecord(invitation: client.inviteTemplate(id: id))
        }
    }

    static func question(id: String, client: HackerRankClient) async throws -> Question {
        let detail = try await client.question(id: id)
        guard detail.question.id == id else {
            throw HackerRankError.decode("The returned question identifier did not match the request.")
        }

        return detail.question
    }
}
