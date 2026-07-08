//
//  AccountActivity.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

/// A read-only, paged view of the current account's audit log (#106) — the organisation's actual
/// change history from `GET /audit_log` (who changed what, when, from where). Distinct from the
/// local Recent Activity, which only records what this app *viewed*. Loads the first page on
/// appearance (and when the account changes) and pages in more on demand.
struct AccountActivityView: View {
    @Environment(AccountStore.self) private var store

    @State private var entries: [AuditLogEntry] = []
    @State private var nextCursor: String?
    @State private var phase: Phase = .loading
    @State private var isLoadingMore = false

    private enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var body: some View {
        Group {
            if let account = store.currentAccount {
                stateView(account: account)
                    .task(id: account.id) { await reload(account: account) }
            } else {
                ContentUnavailableView(
                    "No Account",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Add an account to see its activity.")
                )
            }
        }
    }

    @ViewBuilder
    private func stateView(account: Account) -> some View {
        switch phase {
        case .loading:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .loaded where entries.isEmpty:
            ContentUnavailableView(
                "No Activity",
                systemImage: "clock.arrow.circlepath",
                description: Text("No recent changes are recorded for this account.")
            )

        case .loaded:
            List {
                ForEach(entries) { entry in
                    AuditLogRow(entry: entry)
                }
                if nextCursor != nil {
                    loadMoreRow(account: account)
                }
            }

        case let .failed(message):
            ContentUnavailableView {
                Label("Couldn’t load activity", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") { Task { await reload(account: account) } }
            }
        }
    }

    private func loadMoreRow(account: Account) -> some View {
        HStack {
            Spacer()
            if isLoadingMore {
                ProgressView().controlSize(.small)
            } else {
                Button("Load More") { Task { await loadMore(account: account) } }
                    .buttonStyle(.borderless)
            }
            Spacer()
        }
    }

    private func reload(account: Account) async {
        phase = .loading
        do {
            let page = try await HackerRankClient(account: account).auditLogPage()
            entries = page.items
            nextCursor = page.next
            phase = .loaded
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    private func loadMore(account: Account) async {
        guard let cursor = nextCursor, !isLoadingMore else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }
        if let page = try? await HackerRankClient(account: account).auditLogPage(after: cursor) {
            entries += page.items
            nextCursor = page.next
        }
    }
}

/// One row in the account activity feed (#106): the change summary, who made it, when, and which
/// fields changed.
struct AuditLogRow: View {
    let entry: AuditLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label(entry.headline, systemImage: entry.actionSymbol)
                    .font(.headline)
                Spacer()
                RelativeDateText(iso: entry.createdAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let user = entry.userLabel {
                Text(user)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !entry.modifiedFields.isEmpty {
                Text("Changed: \(entry.modifiedFields.joined(separator: ", "))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Activity rows") {
    let json = #"""
    {"data":[
      {"source_id":"t1","source_type":"test","action":"update",
       "user":{"firstname":"Rhea","lastname":"Recruiter","email":"rhea@example.com"},
       "modified_fields":["name","cutoff_score"],"created_at":"2026-06-20T09:15:00Z"},
      {"source_id":1024,"source_type":"interview","action":"delete",
       "user":"ian@example.com","modified_fields":[],"created_at":"2026-06-18T11:05:00Z"}
    ]}
    """#
    let page = try? JSONDecoder().decode(HackerRankPage<AuditLogEntry>.self, from: Data(json.utf8))
    return VStack(alignment: .leading, spacing: 10) {
        ForEach(page?.data ?? []) { entry in
            AuditLogRow(entry: entry)
            Divider()
        }
    }
    .padding()
    .frame(width: 480)
}
