//
//  NativeAdministration.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit
import Observation

struct NativeBusinessRecord: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let value: HackerRankJSONValue
    var title: String {
        let fields = value.object
        return ["displayName", "diplayName", "userName", "email", "full_name", "name", "action", "source_type", "id"]
            .compactMap { fields[$0]?.text }.first(where: { !$0.isEmpty }) ?? "Event"
    }

    var auditTitle: String {
        let fields = value.object
        let action = fields["action"]?.text ?? "Event"
        let resource = [fields["source_type"]?.text, fields["source_id"]?.text]
            .compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " ")
        return [DisplayFormat.enumLabel(action), resource].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var auditDate: String? {
        DisplayFormat.date(value.object["created_at"]?.text)
    }
}

enum NativeCollectionKind: String {
    case auditOffset, auditCursor, provisioningUsers, provisioningGroups, candidates

    var operationID: String {
        switch self {
        case .auditOffset: "api_list_all_audit_logs"
        case .auditCursor: "api_list_all_audit_logs_cursored"
        case .provisioningUsers: "api_scim_list_users"
        case .provisioningGroups: "api_scim_list_teams"
        case .candidates: "api_search_candidates"
        }
    }

    var scim: Bool {
        self == .provisioningUsers || self == .provisioningGroups
    }

    var isAudit: Bool {
        self == .auditCursor || self == .auditOffset
    }
}

@Observable
final class NativeBusinessCollection {
    var records: [NativeBusinessRecord] = []
    var nextQuery: [URLQueryItem]?
    var loading = false
    var error: String?
    var notice: String?
    private var seenContinuations = Set<String>()
    private var generation = 0

    func clear() {
        generation += 1
        records = []
        nextQuery = nil
        error = nil
        notice = nil
        seenContinuations = []
        loading = false
    }

    func load(kind: NativeCollectionKind, client: HackerRankClient, scimToken: String?,
              query: [URLQueryItem], more: Bool = false) async {
        guard !more || !loading else { return }

        if !more {
            generation += 1
        }
        let requestGeneration = generation

        loading = true
        defer {
            if requestGeneration == generation {
                loading = false
            }
        }
        error = nil
        if !more {
            records = []; nextQuery = nil; seenContinuations = []
        }
        var activeQuery = more ? nextQuery ?? query : query
        if kind.scim, !activeQuery.contains(where: { $0.name == "limit" }) {
            activeQuery.append(URLQueryItem(name: "limit", value: "100"))
        }
        do {
            let response = try await client.executeAPI(kind.operationID, query: activeQuery, scimToken: scimToken)
            try Task.checkCancellation()
            guard requestGeneration == generation else { return }
            guard let payload = response.data else { return }

            let fields = payload.object
            let items = fields["Resources"]?.array ?? fields["data"]?.array ?? payload.array
            var new: [NativeBusinessRecord] = []
            for (index, item) in items.enumerated() {
                let id = item.object["id"]?.text ?? "\(records.count + index)"
                new.append(NativeBusinessRecord(id: id, value: item))
            }
            records = ListPageMerge.merge(records, with: new)
            try setContinuation(Self.continuation(kind: kind, payload: fields, query: activeQuery, count: items.count))
            notice = fields["offset_window_exhausted"] == .bool(true)
                ? "The offset window is exhausted. Switch to cursor pagination to continue through the audit log." : nil
        } catch {
            if !Task.isCancelled, requestGeneration == generation {
                self.error = rankCoverageError(error)
            }
        }
    }

    private func setContinuation(_ query: [URLQueryItem]?) throws {
        nextQuery = query
        if let query {
            let identity = query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&")
            guard seenContinuations.insert(identity).inserted else {
                nextQuery = nil
                throw NativeFormError.invalid("The server repeated a page. Refresh to try again.")
            }
        }
    }

    static func continuation(kind: NativeCollectionKind, payload: [String: HackerRankJSONValue],
                             query: [URLQueryItem], count: Int) throws -> [URLQueryItem]? {
        if kind == .auditCursor {
            guard payload["has_more"] == .bool(true), let cursor = payload["next_cursor"]?.text,
                  !cursor.isEmpty else { return nil }

            return [URLQueryItem(name: "cursor", value: cursor)]
        }
        if let next = payload["next"]?.text, !next.isEmpty,
           let components = URLComponents(string: next), let items = components.queryItems {
            return items
        }
        if kind.scim {
            let offset = Int(query.first(where: { $0.name == "offset" })?.value ?? "0") ?? 0
            let total = payload["totalResults"].flatMap { Int($0.text) }
            guard count > 0, total.map({ offset + count < $0 }) ?? true else { return nil }

            return query.filter { $0.name != "offset" } + [URLQueryItem(name: "offset", value: String(offset + count))]
        }
        return nil
    }
}
