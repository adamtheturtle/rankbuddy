//
//  CreateUserTeamPaging.swift
//  rankbuddy-macos
//

import Foundation

nonisolated enum CreateUserTeamPaging {
    struct NoProgress: LocalizedError {
        var errorDescription: String? {
            "Team loading stopped because HackerRank repeated a page. Reload the sheet to try again."
        }
    }

    static func next(_ cursor: String?, itemCount: Int, seen: inout Set<String>) throws -> String? {
        guard let cursor else { return nil }
        guard itemCount > 0, seen.insert(cursor).inserted else { throw NoProgress() }

        return cursor
    }

    static func appendUnique<Item, ID: Hashable>(
        _ incoming: [Item],
        to loaded: inout [Item],
        seenIDs: inout Set<ID>,
        id: (Item) -> ID
    ) {
        for item in incoming where seenIDs.insert(id(item)).inserted {
            loaded.append(item)
        }
    }
}
