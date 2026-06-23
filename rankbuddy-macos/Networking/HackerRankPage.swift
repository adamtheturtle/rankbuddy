import Foundation
import PaginatedRESTClient

/// The HackerRank for Work list-response envelope: `{ "data": [...], "next": "<url>", ... }`.
///
/// HackerRank paginates by `offset`/`limit` and returns an absolute `next` URL for the
/// following page. `total` is deliberately reported as `nil` so the transport uses its
/// sequential `next`-walk rather than its page-number fast path, which assumes
/// `?page=N` URLs HackerRank does not honour. Pagination metadata other than `data`
/// and `next` is ignored.
nonisolated struct HackerRankPage<Item: Decodable & Sendable>: PagedResponse {
    let data: [Item]
    let next: String?

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
