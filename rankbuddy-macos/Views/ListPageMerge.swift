//
//  ListPageMerge.swift
//  rankbuddy-macos
//

/// Stable-ID reconciliation for paginated lists. Existing row positions are retained, repeated
/// identities are updated with the newest payload, and genuinely new rows append in page order.
nonisolated enum ListPageMerge {
    static func merge<Item: Identifiable>(_ existing: [Item], with incoming: [Item]) -> [Item]
        where Item.ID: Hashable {
        var result: [Item] = []
        var indices: [Item.ID: Int] = [:]

        for item in existing + incoming {
            if let index = indices[item.id] {
                result[index] = item
            } else {
                indices[item.id] = result.count
                result.append(item)
            }
        }
        return result
    }
}
