import BuddyAppKit
import SwiftUI

/// The Questions section: a list of the account's questions with read-only detail.
struct QuestionsScreen: View {
    @Environment(AccountStore.self) private var store

    var body: some View {
        if let account = store.currentAccount {
            LoadableList(
                title: "Questions",
                emptyMessage: "No questions",
                loadPage: { try await HackerRankClient(account: account).questionsPage(after: $0) },
                searchableText: { "\($0.name) \($0.type) \($0.tags?.joined(separator: " ") ?? "")" },
                sortOptions: [
                    SortOption("Name") { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                    SortOption("Type") { $0.type.localizedStandardCompare($1.type) == .orderedAscending },
                    SortOption("Newest") { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
                ],
                restorationKey: "selection.questions.\(account.id)",
                row: { QuestionRow(question: $0) },
                detail: { QuestionDetailView(question: $0) }
            )
        } else {
            NavigationStack {
                NoAccountView()
                    .navigationTitle("Questions")
            }
        }
    }
}

/// One row in the questions list.
struct QuestionRow: View {
    let question: Question
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites

    private var favoriteRef: FavoriteRef? {
        store.currentAccountID.map {
            FavoriteRef(accountID: $0.uuidString, collection: .questions, itemID: question.id, title: question.name)
        }
    }

    private var isFavorite: Bool {
        guard let favoriteRef else { return false }

        return favorites.isFavorite(collection: .questions, accountID: favoriteRef.accountID, itemID: question.id)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(question.name).font(.headline)
                HStack(spacing: 8) {
                    Text(question.type.capitalized)
                    if let languages = DisplayFormat.list(question.languages) {
                        Text(languages)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            FavoriteIndicator(isFavorite: isFavorite)
        }
        .accessibilityElement(children: .combine)
        .rowContextMenu(
            copyLabel: "Copy Name",
            copyText: question.name,
            isFavorite: favoriteRef != nil ? isFavorite : nil,
            toggleFavorite: favoriteRef.map { ref in { favorites.toggle(ref) } }
        )
    }
}

/// Read-only detail for a single question.
struct QuestionDetailView: View {
    let question: Question

    var body: some View {
        Form {
            Section("Question") {
                OptionalRow("Name", question.name)
                OptionalRow("Type", question.type.capitalized)
                OptionalRow("Unique ID", question.uniqueID)
                OptionalRow("Status", question.status?.capitalized)
                OptionalRow("Max score", question.maxScore.map { $0.formatted() })
                OptionalRow("Recommended duration", question.recommendedDuration.map { "\($0) min" })
                OptionalRow("Created", DisplayFormat.date(question.createdAt))
                OptionalRow("Languages", DisplayFormat.list(question.languages))
                OptionalRow("Skills", DisplayFormat.list(question.skills))
            }

            if let tags = question.tags, !tags.isEmpty {
                Section("Tags") {
                    TagList(tags: tags)
                }
            }

            if let statement = question.problemStatement, !statement.isEmpty {
                Section("Problem statement") {
                    HTMLText(html: statement)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(question.name)
    }
}
