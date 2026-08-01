//
//  HackerRankLink.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit
import SafeURLKit
import SwiftUI

/// Parsing + UI for "Open by URL / ID" (#42) — paste a HackerRank URL (or a bare id) and jump
/// straight to the matching test, question, or interview. Mirrors PadBuddy's "Open Pad by URL".
enum HackerRankLink {
    static let defaultAllowedHosts: Set<String> = ["hackerrank.com", "www.hackerrank.com"]
    static let maxOpaqueIDLength = 255
    private static let collections: [String: FavoriteCollection] = [
        "tests": .tests, "questions": .questions, "interviews": .interviews
    ]

    /// Extracts a `(collection, id)` from a pasted HackerRank URL by finding a known collection
    /// segment and taking the segment after it (e.g. `.../tests/abc123/...` → `(.tests, "abc123")`).
    /// Returns `nil` when no known collection segment is present (e.g. a bare id), so the caller
    /// can fall back to a user-chosen type.
    static func parse(
        _ input: String,
        allowedHosts: Set<String> = defaultAllowedHosts
    ) -> (collection: FavoriteCollection, id: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let components = URLComponents(string: trimmed)
        if components?.host != nil {
            let origins = allowedHosts.compactMap { host in
                (try? URLHost.parse(host)).map(OriginRule.host)
            }
            let policy = URLPolicy(
                allowedSchemes: ["https", "http"],
                allowedOrigins: origins,
                portRule: .any,
                allowsFragment: true,
                // A configured self-hosted account may intentionally use an internal name
                // or address. Exact-host matching keeps that widening account-scoped.
                allowsIPLiteralHosts: true,
                allowsSpecialUseHostNames: true,
                allowsSpecialPurposeAddresses: true
            )
            guard policy.allows(trimmed) else { return nil }
        }
        let path = components?.path ?? trimmed
        let segments = path.split(separator: "/").map(String.init)

        for (index, segment) in segments.enumerated() {
            if let collection = collections[segment.lowercased()], index + 1 < segments.count {
                let id = segments[index + 1]
                if isValidOpaqueID(id) {
                    return (collection, id)
                }
            }
        }
        return nil
    }

    /// Service input must be an absolute web URL; unlike the Open sheet it never accepts
    /// path-shaped text or a bare ID because there is no type chooser to disambiguate it.
    static func parseAbsoluteWebURL(
        _ input: String,
        allowedHosts: Set<String> = defaultAllowedHosts
    ) -> (collection: FavoriteCollection, id: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil
        else { return nil }

        return parse(trimmed, allowedHosts: allowedHosts)
    }

    /// Backend IDs are opaque but must remain safe to persist and route. This matches the MCP
    /// prompt boundary so every user-controlled identifier has the same bounded alphabet.
    static func isValidOpaqueID(_ value: String) -> Bool {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-"
        )
        return !value.isEmpty
            && value.count <= maxOpaqueIDLength
            && value.unicodeScalars.allSatisfy(allowed.contains)
    }
}

nonisolated enum OpenLinkAccountSelection {
    static func resolve(isMerged: Bool, selected: UUID?, current: UUID?) -> UUID? {
        isMerged ? selected : current
    }
}

/// Presentation state for the Open-by-URL sheet, set by the File ▸ "Open by URL…" command.
@MainActor
@Observable
final class OpenLinkModel {
    var isPresented = false
}

/// The Open-by-URL/ID sheet: a field plus a type picker (used when a bare id is pasted), which
/// deep-links to the matching item in the current account.
struct OpenLinkSheet: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    @State private var collection: FavoriteCollection = .tests
    @State private var selectedAccountID: UUID?

    private var trimmed: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canOpen: Bool {
        resolvedTarget != nil
    }

    private var resolvedAccountID: UUID? {
        OpenLinkAccountSelection.resolve(
            isMerged: store.isMergedView,
            selected: selectedAccountID,
            current: store.currentAccount?.id
        )
    }

    private var resolvedAccount: Account? {
        guard let resolvedAccountID else { return nil }

        return store.accounts.first { $0.id == resolvedAccountID }
    }

    private var resolvedTarget: (collection: FavoriteCollection, id: String)? {
        guard !trimmed.isEmpty, let account = resolvedAccount else { return nil }

        var allowedHosts = HackerRankLink.defaultAllowedHosts
        if let host = account.baseURL.host {
            allowedHosts.insert(host)
        }
        if let parsed = HackerRankLink.parse(trimmed, allowedHosts: allowedHosts) {
            return parsed
        }
        // A hosted URL that failed parsing must not be reinterpreted as a bare opaque id.
        guard URLComponents(string: trimmed)?.host == nil else { return nil }
        guard HackerRankLink.isValidOpaqueID(trimmed) else { return nil }

        return (collection, trimmed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Open by URL or ID").font(.headline)

            TextField("Paste a HackerRank URL or an ID", text: $input)
                .textFieldStyle(.roundedBorder)

            Picker("Type", selection: $collection) {
                ForEach(FavoriteCollection.allCases, id: \.self) { collection in
                    Text(collection.section.title).tag(collection)
                }
            }
            .pickerStyle(.segmented)
            .help("Used when you paste a bare ID rather than a full URL")

            if store.isMergedView {
                Picker("Account", selection: $selectedAccountID) {
                    Text("Choose the owning account").tag(UUID?.none)
                    ForEach(store.accounts) { account in
                        Text(account.label).tag(Optional(account.id))
                    }
                }
            }

            if resolvedAccountID == nil {
                Label(
                    store.accounts.isEmpty
                        ? "Add an account in Settings before opening HackerRank links."
                        : "Choose the account that owns this HackerRank item.",
                    systemImage: "person.crop.circle.badge.exclamationmark"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            } else if !trimmed.isEmpty, resolvedTarget == nil {
                Label(
                    "Enter a URL from the selected account’s HackerRank host, or enter a bare item ID.",
                    systemImage: "link.badge.plus"
                )
                .font(.callout)
                .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Open") { open() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canOpen)
                    .help(canOpen ? "Open in RankBuddy" : "Select an account and enter a URL or ID")
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func open() {
        guard let account = resolvedAccount, let target = resolvedTarget else { return }

        RankBuddyDeepLink.open(
            collection: target.collection,
            accountID: account.id.uuidString,
            itemID: target.id
        )
        dismiss()
        AppActivator.bringToFront()
    }
}

#Preview {
    OpenLinkSheet()
        .environment(AccountStore.rankBuddy(isTesting: true, seed: [.demo]))
}
