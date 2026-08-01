//
//  ServicesProvider.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit

/// A macOS Service, "Open in RankBuddy", that takes a selected HackerRank URL in any app and
/// deep-links to the matching item (#46). Mirrors PadBuddy's "Open Pad in CoderPad" service.
///
/// The provider is registered at launch (`AppDelegate`) and resolves the current account from
/// its persisted id, so no store reference is needed. The `NSServices` entry that makes the
/// service appear in the Services menu lives in the partial `Info.plist` the app target merges
/// over its generated keys (`INFOPLIST_FILE`), since `NSServices` is an array-of-dicts that no
/// scalar `INFOPLIST_KEY_*` build setting can express (#46).
/// A resolved deep-link target for the Service.
struct ServiceTarget: Equatable {
    let collection: FavoriteCollection
    let accountID: String
    let itemID: String
}

enum ServiceResolutionError: String, Error, Equatable {
    case missingText = "No text was provided to Open in RankBuddy."
    case missingAccount = "Choose a HackerRank account in RankBuddy before using this Service."
    case unsupportedURL = "The selected text is not a supported HackerRank URL."
}

final class ServicesProvider: NSObject {
    /// The service handler named by the Info.plist `NSMessage`. Reads the selected text from the
    /// service pasteboard and opens it. The `NSString` pointer is required by the service
    /// bridging signature.
    @objc func openInRankBuddy(
        _ pasteboard: NSPasteboard,
        userData _: String?,
        // swiftlint:disable:next legacy_objc_type
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        let text = pasteboard.string(forType: .string)
        let currentID = UserDefaults.standard.string(forKey: AccountStore.currentIDDefaultsKey)
        switch Self.resolve(text: text, currentAccountID: currentID) {
        case let .success(target):
            Task { @MainActor in Self.open(target) }

        case let .failure(error):
            // swiftlint:disable:next legacy_objc_type
            errorPointer?.pointee = error.rawValue as NSString
        }
    }

    /// The deep-link target for selected `text` given the current account, or `nil` when it
    /// can't be resolved (not a recognised HackerRank URL, or no current account). Pure, so
    /// it's unit-testable.
    static func target(for text: String, currentAccountID: String?) -> ServiceTarget? {
        try? resolve(text: text, currentAccountID: currentAccountID).get()
    }

    static func resolve(
        text: String?,
        currentAccountID: String?
    ) -> Result<ServiceTarget, ServiceResolutionError> {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.missingText)
        }
        guard let accountID = currentAccountID else {
            return .failure(.missingAccount)
        }
        guard let parsed = HackerRankLink.parseAbsoluteWebURL(text) else {
            return .failure(.unsupportedURL)
        }

        return .success(ServiceTarget(
            collection: parsed.collection,
            accountID: accountID,
            itemID: parsed.id
        ))
    }

    /// Resolves and opens the selected text against the current account, bringing the app forward.
    @MainActor
    static func open(_ text: String) {
        let currentID = UserDefaults.standard.string(forKey: AccountStore.currentIDDefaultsKey)
        guard let target = target(for: text, currentAccountID: currentID) else { return }

        open(target)
    }

    @MainActor
    private static func open(_ target: ServiceTarget) {
        RankBuddyDeepLink.open(collection: target.collection, accountID: target.accountID, itemID: target.itemID)
        AppActivator.bringToFront()
        NSApp.windows.first(where: \.canBecomeMain)?.makeKeyAndOrderFront(nil)
    }
}
