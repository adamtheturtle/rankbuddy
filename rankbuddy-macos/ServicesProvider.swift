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
    @MainActor @objc func openInRankBuddy(
        _ pasteboard: NSPasteboard,
        userData _: String?,
        // swiftlint:disable:next legacy_objc_type
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString>?
    ) {
        let text = pasteboard.string(forType: .string)
        let currentID = UserDefaults.standard.string(forKey: AccountStore.currentIDDefaultsKey)
        let accounts = SharedAccountStore.resolve().accounts
        let allowedHosts = Self.allowedHosts(
            currentAccountID: currentID,
            accounts: accounts
        )
        switch Self.resolve(
            text: text,
            currentAccountID: currentID,
            accounts: accounts,
            allowedHosts: allowedHosts
        ) {
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
    static func target(
        for text: String,
        currentAccountID: String?,
        accounts: [Account],
        allowedHosts: Set<String> = HackerRankLink.defaultAllowedHosts
    ) -> ServiceTarget? {
        try? resolve(
            text: text,
            currentAccountID: currentAccountID,
            accounts: accounts,
            allowedHosts: allowedHosts
        ).get()
    }

    static func resolve(
        text: String?,
        currentAccountID: String?,
        accounts: [Account],
        allowedHosts: Set<String> = HackerRankLink.defaultAllowedHosts
    ) -> Result<ServiceTarget, ServiceResolutionError> {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.missingText)
        }
        guard let accountID = currentAccountID,
              let encodedID = UUID(uuidString: accountID),
              accounts.contains(where: { $0.id == encodedID })
        else {
            return .failure(.missingAccount)
        }
        guard let parsed = HackerRankLink.parseAbsoluteWebURL(text, allowedHosts: allowedHosts) else {
            return .failure(.unsupportedURL)
        }

        return .success(ServiceTarget(
            collection: parsed.collection,
            accountID: accountID,
            itemID: parsed.id
        ))
    }

    static func allowedHosts(currentAccountID: String?, accounts: [Account]) -> Set<String> {
        var hosts = HackerRankLink.defaultAllowedHosts
        if let currentAccountID,
           let id = UUID(uuidString: currentAccountID),
           let host = accounts.first(where: { $0.id == id })?.baseURL.host {
            hosts.insert(host)
        }
        return hosts
    }

    @MainActor
    private static func open(_ target: ServiceTarget) {
        RankBuddyDeepLink.open(collection: target.collection, accountID: target.accountID, itemID: target.itemID)
        AppActivator.bringToFront()
        NSApp.windows.first(where: \.canBecomeMain)?.makeKeyAndOrderFront(nil)
    }
}
