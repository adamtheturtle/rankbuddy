//
//  HackerRankLink.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit
import SwiftUI

/// Parsing + UI for "Open by URL / ID" (#42) — paste a HackerRank URL (or a bare id) and jump
/// straight to the matching test, question, or interview. Mirrors PadBuddy's "Open Pad by URL".
enum HackerRankLink {
    private static let collections: [String: FavoriteCollection] = [
        "tests": .tests, "questions": .questions, "interviews": .interviews
    ]

    /// Extracts a `(collection, id)` from a pasted HackerRank URL by finding a known collection
    /// segment and taking the segment after it (e.g. `.../tests/abc123/...` → `(.tests, "abc123")`).
    /// Returns `nil` when no known collection segment is present (e.g. a bare id), so the caller
    /// can fall back to a user-chosen type.
    static func parse(_ input: String) -> (collection: FavoriteCollection, id: String)? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = URLComponents(string: trimmed)?.path ?? trimmed
        let segments = path.split(separator: "/").map(String.init)

        for (index, segment) in segments.enumerated() {
            if let collection = collections[segment.lowercased()], index + 1 < segments.count {
                let id = segments[index + 1]
                if !id.isEmpty { return (collection, id) }
            }
        }
        return nil
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
        !trimmed.isEmpty && resolvedAccountID != nil
    }

    private var resolvedAccountID: UUID? {
        OpenLinkAccountSelection.resolve(
            isMerged: store.isMergedView,
            selected: selectedAccountID,
            current: store.currentAccount?.id
        )
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
        guard !trimmed.isEmpty, let accountID = resolvedAccountID?.uuidString else { return }

        let target = HackerRankLink.parse(trimmed) ?? (collection: collection, id: trimmed)
        RankBuddyDeepLink.open(collection: target.collection, accountID: accountID, itemID: target.id)
        dismiss()
        AppActivator.bringToFront()
    }
}

#Preview {
    OpenLinkSheet()
        .environment(AccountStore.rankBuddy(isTesting: true, seed: [.demo]))
}
