//
//  ServicesProvider.swift
//  rankbuddy-macos
//

import AppKit

/// A macOS Service, "Open in RankBuddy", that takes a selected HackerRank URL in any app and
/// deep-links to the matching item (#46). Mirrors PadBuddy's "Open Pad in CoderPad" service.
///
/// The runtime side here is complete — the provider is registered at launch and resolves the
/// current account from its persisted id, so no store reference is needed. The service only
/// *appears* in the Services menu once an `NSServices` entry is declared in the app's
/// Info.plist; RankBuddy uses a generated Info.plist, so adding that entry is a project-file
/// change for the maintainer (see the `NSServices` snippet on issue #46).
/// A resolved deep-link target for the Service.
struct ServiceTarget: Equatable {
    let collection: FavoriteCollection
    let accountID: String
    let itemID: String
}

final class ServicesProvider: NSObject {
    /// The service handler named by the Info.plist `NSMessage`. Reads the selected text from the
    /// service pasteboard and opens it. The `NSString` pointer is required by the service
    /// bridging signature.
    @objc func openInRankBuddy(
        _ pasteboard: NSPasteboard,
        userData _: String?,
        // swiftlint:disable:next legacy_objc_type
        error _: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        guard let text = pasteboard.string(forType: .string) else { return }

        Task { @MainActor in Self.open(text) }
    }

    /// The deep-link target for selected `text` given the current account, or `nil` when it
    /// can't be resolved (not a recognised HackerRank URL, or no current account). Pure, so
    /// it's unit-testable.
    static func target(for text: String, currentAccountID: String?) -> ServiceTarget? {
        guard let accountID = currentAccountID, let parsed = HackerRankLink.parse(text) else { return nil }

        return ServiceTarget(collection: parsed.collection, accountID: accountID, itemID: parsed.id)
    }

    /// Resolves and opens the selected text against the current account, bringing the app forward.
    @MainActor
    static func open(_ text: String) {
        let currentID = UserDefaults.standard.string(forKey: AccountStore.currentIDDefaultsKey)
        guard let target = target(for: text, currentAccountID: currentID) else { return }

        RankBuddyDeepLink.open(collection: target.collection, accountID: target.accountID, itemID: target.itemID)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: \.canBecomeMain)?.makeKeyAndOrderFront(nil)
    }
}
