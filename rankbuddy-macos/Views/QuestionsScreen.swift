//
//  QuestionsScreen.swift
//  rankbuddy-macos
//

import BuddyAppKit
import SwiftUI

/// The Questions section: a list of the account's questions with read-only detail.
struct QuestionsScreen: View {
    @Environment(AccountStore.self) private var store
    @Environment(FavoritesStore.self) private var favorites
    @Environment(\.openWindow) private var openWindow

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
                    SortOption("Name") { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
                    SortOption("Type") { $0.type.localizedStandardCompare($1.type) == .orderedAscending },
                    SortOption("Newest") { ($0.createdAt ?? "") > ($1.createdAt ?? "") }
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
                            title: question.name
                        ),
                        openInWindow: { openWindow(value: DetailWindowValue.question(question)) }
                    )
                },
                onFirstPage: { questions in
                    RecentActivityStore.shared.record(
                        questions.map {
                            RecentItem(collection: .questions, id: $0.id, title: $0.name, subtitle: $0.type.capitalized)
                        },
                        for: .questions,
                        account: account.id
                    )
                },
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
                rowDate: { DisplayFormat.parseDate($0.createdAt) },
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

    /// Loads one merged page of questions across every configured account (#17).
    private func loadMergedQuestions(_: String?) async throws -> Page<AccountScoped<Question>> {
        let items = try await MergedLoader.firstPages(accounts: store.accounts) {
            try await HackerRankClient(account: $0).questionsPage().items
        }
        return Page(items: items, next: nil)
    }

    /// Questions merged across every configured account (#17).
    private var mergedList: some View {
        LoadableList(
            title: "Questions",
            emptyMessage: "No questions",
            loadPage: loadMergedQuestions,
            searchableText: { "\($0.item.name) \($0.item.type) \($0.account.label)" },
            sortOptions: [
                SortOption("Name") { $0.item.name.localizedStandardCompare($1.item.name) == .orderedAscending },
                SortOption("Account", by: AccountScoped.byAccountLabel),
                SortOption("Type") { $0.item.type.localizedStandardCompare($1.item.type) == .orderedAscending }
            ],
            contextMenu: { rowMenuItems(copyLabel: "Copy Name", copyText: $0.item.name) },
            rowDate: { DisplayFormat.parseDate($0.item.createdAt) },
            row: {
                MergedRow(title: $0.item.name, subtitle: $0.item.type.capitalized, account: $0.account)
            },
            detail: { QuestionDetailView(question: $0.item) }
        )
    }
}

/// One row in the questions list.
struct QuestionRow: View {
    let question: Question

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(question.name).font(.callout.weight(.medium))
                HStack(spacing: 8) {
                    Text(question.type.capitalized)
                    if let languages = DisplayFormat.languages(question.languages) {
                        Text(languages)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
    }
}

/// Read-only detail for a single question. Beyond the list row's fields, it fetches the richer
/// single-question read on selection (#105) and merges the MCQ options, the (sensitive) correct
/// answer — gated behind an explicit reveal — and the author's internal notes. The fetch is
/// best-effort and skipped in the merged view, where the owning account is ambiguous.
struct QuestionDetailView: View {
    let question: Question
    @Environment(AccountStore.self) private var store
    @State private var detail: QuestionDetail?
    @State private var answerRevealed = false

    var body: some View {
        Form {
            InspectorHeader(title: question.name, badges: question.inspectorBadges)

            Section("Properties") {
                OptionalRow("Type", question.type.capitalized)
                OptionalRow("Unique ID", question.uniqueID)
                OptionalRow("Status", question.status?.capitalized)
                OptionalRow("Max score", question.maxScore.map { $0.formatted() })
                OptionalRow("Recommended duration", question.recommendedDuration.map { "\($0) min" })
                OptionalRow("Created", DisplayFormat.date(question.createdAt))
                OptionalRow("Languages", DisplayFormat.languages(question.languages))
                OptionalRow("Skills", DisplayFormat.list(question.skills))
            }

            if let tags = question.tags, !tags.isEmpty {
                Section("Tags") {
                    TagList(tags: tags)
                }
            }

            if let detail, !detail.options.isEmpty {
                Section("Options") {
                    ForEach(Array(detail.options.enumerated()), id: \.offset) { index, option in
                        Label(option, systemImage: isCorrect(option) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isCorrect(option) ? Color.green : Color.primary)
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityLabel(isCorrect(option) ? "\(option), correct answer" : option)
                            .id(index)
                    }
                }
            }

            if let answer = detail?.answer, !answer.isEmpty {
                Section("Answer") {
                    if answerRevealed {
                        Text(answer).textSelection(.enabled)
                    } else {
                        Button {
                            answerRevealed = true
                        } label: {
                            Label("Reveal answer", systemImage: "eye")
                        }
                        .help("Show the correct answer")
                    }
                }
            }

            if let statement = question.problemStatement, !statement.isEmpty {
                Section("Problem statement") {
                    HighlightedHTMLText(html: statement)
                }
            }

            if let notes = detail?.internalNotes, !notes.isEmpty {
                Section("Internal notes") {
                    HTMLText(html: notes)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(question.name)
        .task(id: question.id) { await loadDetail() }
        .advertisesItemActivity(collection: .questions, itemID: question.id, title: question.name)
        // Print and Markdown export are off the bar by default but one Customize Toolbar away.
        .toolbar(id: "questionDetail") {
            ToolbarItem(id: "print") {
                PrintReportButton(jobTitle: "Question: \(question.name)") {
                    QuestionReport(question: question)
                }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "exportMarkdown") {
                MarkdownExportButton(suggestedName: question.name) { MarkdownExport.question(question) }
            }
            .defaultCustomization(.hidden)
        }
    }

    /// Whether an option matches the (revealed) correct answer, so it can be ticked in the list.
    /// Only highlights once the answer has been revealed, keeping the answer hidden by default.
    private func isCorrect(_ option: String) -> Bool {
        answerRevealed && detail?.answer == option
    }

    /// Fetches the richer question detail on selection (#105). Best-effort — a failure leaves the
    /// base list-row detail intact — and skipped in the merged view, where the owning account is
    /// ambiguous, so the wrong account is never queried. Re-hides the answer for each question.
    private func loadDetail() async {
        detail = nil
        answerRevealed = false
        guard !store.isMergedView, let account = store.currentAccount else { return }

        detail = try? await HackerRankClient(account: account).question(id: question.id)
    }
}
