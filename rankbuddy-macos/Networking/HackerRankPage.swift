import BuddyAppKit
import Foundation
import PaginatedRESTClient

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
        let lenient = try container.decode([LenientElement<Item>].self, forKey: .data)
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
