//
//  Handoff.swift
//  rankbuddy-macos
//

import BuddyAppKit
import SwiftUI

/// Handoff / Continuity (#98): advertises the test, question, or interview currently on screen
/// as an `NSUserActivity`, so the system can Hand Off the live item to another device, surface
/// it in Spotlight, and offer it as a Siri Suggestion. Restoration routes back through the
/// app's normal deep-link open path (`RankBuddyDeepLink`); when the app isn't installed the
/// system falls back to the activity's `webpageURL` in the browser.
///
/// Mirrors PadBuddy's `PadHandoff`, mapped onto RankBuddy's existing deep-link infrastructure
/// (#42/#24) — the same per-account routing the Spotlight open intent and favourites use.
enum RankBuddyUserActivity {
    /// The activity type, also declared in `NSUserActivityTypes` (Info.plist) so the system
    /// will advertise and continue it.
    nonisolated static let activityType = "com.adamdangoor.rankbuddy.viewingItem"

    /// `userInfo` keys carrying just enough to re-open the item in-app — no token or PII.
    nonisolated enum Key {
        static let collection = "collection"
        static let accountID = "accountID"
        static let itemID = "itemID"
    }

    /// The account-scoped identity of a viewable item — everything the deep-link open path
    /// needs, and exactly what travels in the activity's `userInfo`.
    nonisolated struct ItemRef: Hashable {
        let collection: FavoriteCollection
        let accountID: String
        let itemID: String
    }

    /// The HackerRank web URL for an item, built from the account's base host and the same
    /// `/x/<collection>/<id>` shape the live interview URLs use. Used as the activity's
    /// `webpageURL` so Handoff to a device without the app falls back to the browser.
    nonisolated static func webURL(
        base: URL,
        collection: FavoriteCollection,
        itemID: String
    ) -> URL? {
        URL(string: "/x/\(collection.rawValue)/\(itemID)", relativeTo: base)?.absoluteURL
    }

    /// Populates an activity to advertise the given item. The activity is eligible for Handoff
    /// and Spotlight search; `webpageURL` (when provided) drives the browser fallback and a
    /// stable Spotlight identity. (`isEligibleForPrediction` is iOS-only, so it is omitted here.)
    nonisolated static func configure(
        _ activity: NSUserActivity,
        ref: ItemRef,
        title: String,
        webURL: URL?
    ) {
        activity.title = title
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        activity.webpageURL = webURL
        activity.userInfo = [
            Key.collection: ref.collection.rawValue,
            Key.accountID: ref.accountID,
            Key.itemID: ref.itemID
        ]
        activity.requiredUserInfoKeys = [Key.collection, Key.accountID, Key.itemID]
    }

    /// The routing target carried by a continued activity's `userInfo`, or `nil` when it does
    /// not parse (a foreign or malformed activity). Pure, so it is unit-tested directly.
    nonisolated static func target(userInfo: [AnyHashable: Any]?) -> ItemRef? {
        guard let userInfo,
              let raw = userInfo[Key.collection] as? String,
              let collection = FavoriteCollection(rawValue: raw),
              let accountID = userInfo[Key.accountID] as? String, !accountID.isEmpty,
              let itemID = userInfo[Key.itemID] as? String, !itemID.isEmpty
        else { return nil }

        return ItemRef(collection: collection, accountID: accountID, itemID: itemID)
    }

    /// Continues an activity: deep-links to the item in-app when the `userInfo` resolves,
    /// otherwise opens its `webpageURL` through the browser preference (#63). Returns whether
    /// it handled the activity.
    @MainActor @discardableResult
    static func restore(_ activity: NSUserActivity) -> Bool {
        if let target = target(userInfo: activity.userInfo) {
            RankBuddyDeepLink.open(
                collection: target.collection, accountID: target.accountID, itemID: target.itemID
            )
            NSApp.activate(ignoringOtherApps: true)
            return true
        }
        if let url = activity.webpageURL {
            BrowserSettings.open(url)
            return true
        }
        return false
    }
}

/// Advertises the item a detail view is showing as an `NSUserActivity` while the view is on
/// screen (#98). Reads the current account from the environment so each detail view only has to
/// declare its own item.
private struct ItemUserActivityModifier: ViewModifier {
    @Environment(AccountStore.self) private var store
    let collection: FavoriteCollection
    let itemID: String
    let title: String
    /// A model-provided web URL (e.g. `Interview.url`) preferred over the derived one.
    let webURL: URL?

    func body(content: Content) -> some View {
        content.userActivity(RankBuddyUserActivity.activityType) { activity in
            guard let account = store.currentAccount else { return }

            RankBuddyUserActivity.configure(
                activity,
                ref: RankBuddyUserActivity.ItemRef(
                    collection: collection, accountID: account.id.uuidString, itemID: itemID
                ),
                title: title,
                webURL: webURL ?? RankBuddyUserActivity.webURL(
                    base: account.baseURL, collection: collection, itemID: itemID
                )
            )
        }
    }
}

extension View {
    /// Advertises the shown item for Handoff / Spotlight / Siri while this view is visible (#98).
    func advertisesItemActivity(
        collection: FavoriteCollection,
        itemID: String,
        title: String,
        webURL: URL? = nil
    ) -> some View {
        modifier(ItemUserActivityModifier(
            collection: collection, itemID: itemID, title: title, webURL: webURL
        ))
    }
}
