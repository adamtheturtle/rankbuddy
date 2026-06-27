//
//  HackerRankPage.swift
//  rankbuddy-macos
//

import Foundation
import PaginatedRESTClient

/// Wraps a decodable element so a per-element decode failure yields `nil` instead of failing
/// the whole array. A local, `nonisolated` equivalent of buddy-kit's `LenientElement` so its
/// `value` can be read from the off-main, nonisolated page decode (buddy-kit's type is
/// main-actor-isolated under that module's default isolation).
private nonisolated struct LenientItem<Wrapped: Decodable>: Decodable {
    let value: Wrapped?

    init(from decoder: any Decoder) {
        value = try? decoder.singleValueContainer().decode(Wrapped.self)
    }
}

/// The HackerRank for Work list-response envelope: `{ "data": [...], "next": "<url>", ... }`.
///
/// HackerRank paginates by `offset`/`limit` and returns an absolute `next` URL for the
/// following page. `total` is deliberately reported as `nil` so the transport uses its
/// sequential `next`-walk rather than its page-number fast path, which assumes
/// `?page=N` URLs HackerRank does not honour. Pagination metadata other than `data`
/// and `next` is ignored.
///
/// `data` is decoded **leniently**: any single record that fails to decode is dropped
/// rather than failing the whole page, so one malformed item on a live account never breaks
/// the entire list (defense against the class of bug behind #5/#34). The models are already
/// resilient (every non-identifying field optional); this is the page-level backstop.
nonisolated struct HackerRankPage<Item: Decodable & Sendable>: PagedResponse {
    let data: [Item]
    let next: String?

    enum CodingKeys: String, CodingKey {
        case data
        case next
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let lenient = try container.decode([LenientItem<Item>].self, forKey: .data)
        data = lenient.compactMap(\.value)
        next = try container.decodeIfPresent(String.self, forKey: .next)
    }

    var pageItems: [Item] {
        data
    }

    var nextPage: String? {
        next
    }

    var total: Int? {
        nil
    }
}
