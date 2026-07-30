//
//  QuestionsScreen.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

/// The Questions section: a list of the account's questions with read-only detail.
struct QuestionsScreen: View {
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.openWindow) private var openWindow
    @Environment(\.undoManager) private var undoManager
    @State private var reloadToken = 0
    @State private var createPresented = false

    var body: some View {
        if store.isMergedView {
            mergedList
        } else if let account = store.currentAccount {
            LoadableList(
                title: "Questions",
                emptyMessage: "No questions",
                loadPage: { try await HackerRankClient(account: account).questionsPage(after: $0) },
                searchableText: { "\($0.name) \($0.type) \($0.tags?.joined(separator: " ") ?? "")" },
                sortOptions: [
                    SortOption("Name", systemImage: "textformat", kind: .text) {
                        $0.name.localizedStandardCompare($1.name) == .orderedAscending
                    },
                    SortOption("Type", systemImage: "tag", kind: .text) {
                        $0.type.localizedStandardCompare($1.type) == .orderedAscending
                    },
                    SortOption("Date Created", systemImage: "calendar", kind: .date,
                               isMissing: { $0.createdAt == nil }, by: {
                                   ($0.createdAt ?? "") > ($1.createdAt ?? "")
                               })
                ],
                restorationKey: "selection.questions.\(account.id)",
                contextMenu: { question in
                    rowMenuItems(
                        copyLabel: "Copy Name",
                        copyText: question.name,
                        favorite: favorites.menuState(
                            accountID: store.currentAccountID,
                            collection: .questions,
                            itemID: question.id,
                            title: question.name,
                            undoManager: undoManager
                        ),
                        openInWindow: {
                            openWindow(value: DetailWindowValue.question(question, accountID: account.id))
                        }
                    )
                },
                openInWindow: {
                    openWindow(value: DetailWindowValue.question($0, accountID: account.id))
                },
                onOpen: { question in
                    RecentActivityStore.shared.record(
                        [RecentItem(
                            collection: .questions,
                            id: question.id,
                            title: question.name,
                            subtitle: DisplayFormat.enumLabel(question.type)
                        )],
                        for: .questions,
                        account: account.id
                    )
                },
                onItemsLoaded: { questions in
                    favorites.refreshMetadata(from: questions.map {
                        FavoriteRef(
                            accountID: account.id.uuidString,
                            collection: .questions,
                            itemID: $0.id,
                            title: $0.name
                        )
                    })
                },
                accessoryToolbar: { AnyView(createButton) },
                primaryMenuAction: AppCommandContext.Action(title: "New Question…") { createPresented = true },
                reloadToken: reloadToken,
                csvExport: { CSVExport.questions($0) },
                csvFilename: "questions",
                favoriteRef: { question in
                    store.currentAccountID.map {
                        FavoriteRef(
                            accountID: $0.uuidString, collection: .questions,
                            itemID: question.id, title: question.name
                        )
                    }
                },
                rowTransfer: { question in
                    RowTransfer(title: question.name, subtitle: DisplayFormat.enumLabel(question.type), fields: [
                        ("Name", question.name),
                        ("Type", DisplayFormat.enumLabel(question.type)),
                        ("Unique ID", question.uniqueID ?? ""),
                        ("Status", DisplayFormat.enumLabel(question.status) ?? "")
                    ])
                },
                rowDate: { DisplayFormat.parseDate($0.createdAt) },
                row: { QuestionRow(question: $0) },
                detail: {
                    QuestionDetailView(question: $0, account: account) { reloadToken += 1 }
                }
            )
            .sheet(isPresented: $createPresented) {
                NewQuestionSheet(account: account) { reloadToken += 1 }
            }
        } else {
            NavigationStack {
                NoAccountView()
                    .navigationTitle("Questions")
            }
        }
    }

    private var createButton: some View {
        Button {
            createPresented = true
        } label: {
            Label("New Question…", systemImage: "plus.rectangle.on.rectangle")
        }
        .help("Create a question")
    }

    /// Loads one merged page of questions across every configured account (#17).
    private func loadMergedQuestions(_ cursor: String?) async throws -> Page<AccountScoped<Question>> {
        try await MergedLoader.page(accounts: store.accounts, cursor: cursor) {
            try await HackerRankClient(account: $0).questionsPage(after: $1)
        }
    }

    /// Questions merged across every configured account (#17).
    private var mergedList: some View {
        LoadableList(
            title: "Questions",
            emptyMessage: "No questions",
            loadPage: loadMergedQuestions,
            searchableText: { "\($0.item.name) \($0.item.type) \($0.account.label)" },
            sortOptions: [
                SortOption("Name", systemImage: "textformat", kind: .text) {
                    $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending
                },
                SortOption("Account", systemImage: "person.crop.circle", kind: .text,
                           by: AccountScoped.byAccountLabel),
                SortOption("Type", systemImage: "tag", kind: .text) {
                    $0.item.type.localizedStandardCompare($1.item.type) == .orderedAscending
                }
            ],
            contextMenu: { scoped in
                rowMenuItems(
                    copyLabel: "Copy Name",
                    copyText: scoped.item.name,
                    openInWindow: {
                        openWindow(value: DetailWindowValue.question(scoped.item, accountID: scoped.account.id))
                    }
                )
            },
            openInWindow: {
                openWindow(value: DetailWindowValue.question($0.item, accountID: $0.account.id))
            },
            rowTransfer: { scoped in
                RowTransfer(title: scoped.item.name, subtitle: scoped.account.label, fields: [
                    ("Name", scoped.item.name),
                    ("Account", scoped.account.label),
                    ("Type", DisplayFormat.enumLabel(scoped.item.type)),
                    ("Unique ID", scoped.item.uniqueID ?? "")
                ])
            },
            rowDate: { DisplayFormat.parseDate($0.item.createdAt) },
            row: {
                MergedRow(title: $0.item.name, subtitle: DisplayFormat.enumLabel($0.item.type), account: $0.account)
            },
            detail: { QuestionDetailView(question: $0.item, account: $0.account) }
        )
    }
}

/// One row in the questions list.
struct QuestionRow: View {
    let question: Question

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(question.name).listRowTitleStyle(fullText: question.name)
                HStack(spacing: 8) {
                    Text(DisplayFormat.enumLabel(question.type))
                    if let languages = DisplayFormat.languages(question.languages) {
                        Text(languages)
                    }
                }
                .listRowMetadataStyle()
            }
            .listRowTextColumn()
            Spacer(minLength: 12)
        }
        .accessibilityElement(children: .combine)
    }
}
