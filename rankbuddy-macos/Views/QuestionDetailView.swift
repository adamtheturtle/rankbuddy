//
//  QuestionDetailView.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

// The inspector and its export projection intentionally share one source file.
// swiftlint:disable file_length

struct QuestionEditOverlay {
    private(set) var name: String?
    private(set) var options = QuestionWriteOptions()

    mutating func merge(name: String?, options update: QuestionWriteOptions) {
        self.name = name ?? self.name
        options = QuestionWriteOptions(
            status: update.status ?? options.status,
            languages: update.languages ?? options.languages,
            problemStatement: update.problemStatement ?? options.problemStatement,
            recommendedDuration: update.recommendedDuration ?? options.recommendedDuration,
            tags: update.tags ?? options.tags,
            maxScore: update.maxScore ?? options.maxScore,
            skills: update.skills ?? options.skills
        )
    }

    func applying(to question: Question) -> Question {
        question.applying(name: name, options)
    }
}

/// Detail for a single question. Beyond the list row's fields, it fetches the richer
/// single-question read on selection (#105) and merges the MCQ options, the (sensitive) correct
/// answer — gated behind an explicit reveal — and the author's internal notes. The fetch is
/// best-effort and skipped in the merged view, where the owning account is ambiguous.
/// Outside the merged view the title renames in place and the metadata saves per field via
/// `updateQuestion`; coding questions also gain testcase and code-stub actions (#147).
struct QuestionDetailView: View {
    let question: Question
    let account: Account?
    var onChanged: () -> Void = {}
    @Environment(AccountStore.self) private var store
    @Environment(\.controlActiveState) private var controlActiveState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppCommandContext.self) private var commandContext
    @State private var detail: QuestionDetail?
    @State private var answerRevealed = false
    @State private var deletePresented = false
    @State private var deleteError: String?
    @State private var editError: String?
    @State private var detailQuestion: Question?
    /// Local field overlay for saved edits; fresh server metadata remains the underlying model.
    @State private var editOverlay = QuestionEditOverlay()
    @State private var addTestcasePresented = false
    @State private var deleteTestcasesPresented = false
    @State private var generateStubsPresented = false
    @State private var customStubPresented = false
    @State private var commandOwner = UUID()

    init(question: Question, account: Account? = nil, onChanged: @escaping () -> Void = {}) {
        self.question = question
        self.account = account
        self.onChanged = onChanged
    }

    private var owningAccount: Account? {
        account ?? (store.isMergedView ? nil : store.currentAccount)
    }

    /// The freshest copy of the question: saved edits overlay the detail metadata, then the list row.
    private var displayed: Question {
        editOverlay.applying(to: detailQuestion ?? question)
    }

    private var reportData: QuestionReportData {
        QuestionReportData(question: displayed, detail: detail, includeCorrectAnswer: answerRevealed)
    }

    /// Editing needs a single owning account, so the merged view stays read-only.
    private var canEdit: Bool {
        owningAccount != nil
    }

    /// The problem statement, or `nil` when it is missing or renders as blank — HackerRank
    /// sometimes stores markup like `<p><br></p>` with no visible text, which would otherwise
    /// pass a plain emptiness check and show as an empty box.
    private var problemStatement: String? {
        guard let statement = displayed.problemStatement,
              !MarkdownExport.plainText(fromHTML: statement).isEmpty else { return nil }

        return statement
    }

    /// The rename hook for the header; `nil` (a static title) when editing is unavailable.
    private var renameAction: ((String) async -> Bool)? {
        guard canEdit else { return nil }

        return { newName in
            await save(name: newName)
        }
    }

    var body: some View {
        Form {
            InspectorHeader(title: displayed.name, badges: displayed.inspectorBadges, onRename: renameAction)

            Section("Properties") {
                OptionalRow("Unique ID", displayed.uniqueID)
                OptionalRow("Created", DisplayFormat.date(displayed.createdAt))
                if canEdit {
                    editableRows
                } else {
                    OptionalRow("Max score", displayed.maxScore.map { $0.formatted() })
                    OptionalRow("Recommended duration", displayed.recommendedDuration.map { "\($0) minutes" })
                    OptionalRow("Languages", DisplayFormat.languages(displayed.languages))
                    OptionalRow("Skills", DisplayFormat.list(displayed.skills))
                }
            }

            if !canEdit, let tags = displayed.tags, !tags.isEmpty {
                Section("Tags") {
                    TagList(tags: tags)
                }
            }

            if canEdit, displayed.type.lowercased() == "coding" {
                codingSection
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

            if canEdit {
                Section("Problem statement") {
                    // Edits work on the raw source; display renders HackerRank's HTML.
                    InlineEditableText(
                        text: problemStatement ?? "",
                        placeholder: "Add a problem statement",
                        rendersHTML: true
                    ) { newValue in
                        await save(QuestionWriteOptions(problemStatement: newValue))
                    }
                }
            } else if let statement = problemStatement {
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
        .navigationTitle(displayed.name)
        .task(id: question.id) { await loadDetail() }
        .onAppear { registerDetailCommands() }
        .activatesDetailCommands(in: commandContext, owner: commandOwner)
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                answerRevealed = false
            }
        }
        .onChange(of: controlActiveState) { _, state in
            if state != .key {
                answerRevealed = false
            }
        }
        .onDisappear {
            answerRevealed = false
            commandContext.clearDetailActions(owner: commandOwner)
        }
        .advertisesItemActivity(collection: .questions, itemID: question.id, title: displayed.name)
        // Share and Open stay in the bar; Print and Markdown export are off the bar by default but
        // one Customize Toolbar away.
        .toolbar(id: "questionDetail") {
            DetailLinkToolbarContent(
                url: owningAccount.flatMap {
                    RankBuddyUserActivity.webURL(base: $0.baseURL, collection: .questions, itemID: question.id)
                },
                noun: "question"
            )
            ToolbarItem(id: "print") {
                PrintReportButton(jobTitle: "Question: \(displayed.name)") {
                    QuestionReport(data: reportData)
                }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "exportMarkdown") {
                let snapshot = reportData
                MarkdownExportButton(suggestedName: snapshot.question.name) { MarkdownExport.question(snapshot) }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "delete") {
                Button(role: .destructive) {
                    deletePresented = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete this question")
                .disabled(owningAccount == nil)
            }
            .defaultCustomization(.hidden)
        }
        .confirmationDialog("Delete “\(displayed.name)”?", isPresented: $deletePresented, titleVisibility: .visible) {
            Button("Delete Question", role: .destructive) {
                Task { await deleteQuestion() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the question on HackerRank. This can’t be undone.")
        }
        .alert("Couldn’t delete question", isPresented: deleteErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
        .alert("Couldn’t update question", isPresented: editErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(editError ?? "")
        }
        .sheet(isPresented: $addTestcasePresented) {
            if let account = owningAccount {
                AddTestcaseSheet(questionID: question.id, account: account) {}
            }
        }
        .sheet(isPresented: $generateStubsPresented) {
            if let account = owningAccount {
                GenerateCodeStubsSheet(questionID: question.id, account: account)
            }
        }
        .sheet(isPresented: $customStubPresented) {
            if let account = owningAccount {
                CustomCodeStubSheet(questionID: question.id, account: account)
            }
        }
        .confirmationDialog(
            "Delete all testcases?",
            isPresented: $deleteTestcasesPresented,
            titleVisibility: .visible
        ) {
            Button("Delete All Testcases", role: .destructive) {
                Task { await deleteAllTestcases() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every testcase from “\(displayed.name)” on HackerRank. This can’t be undone.")
        }
    }
}

// MARK: - Editing, destructive actions, and detail loading

extension QuestionDetailView {
    private var deleteErrorPresented: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    private var editErrorPresented: Binding<Bool> {
        Binding(get: { editError != nil }, set: { if !$0 { editError = nil } })
    }

    /// Per-field editable rows: each saves immediately and reverts if the write fails.
    @ViewBuilder
    private var editableRows: some View {
        EditableTextRow(label: "Max score", value: displayed.maxScore.map { $0.formatted() } ?? "") { newValue in
            guard newValue.isEmpty || QuestionEditValidation.maxScore(from: newValue) != nil else {
                editError = "Max score must be a finite number of zero or greater."
                return false
            }

            return await save(QuestionWriteOptions(maxScore: QuestionEditValidation.maxScore(from: newValue)))
        }
        EditableNumberRow(label: "Recommended duration (minutes)", value: displayed.recommendedDuration) { newValue in
            guard QuestionEditValidation.isValidRecommendedDuration(newValue) else {
                editError = "Recommended duration must be between 0 and 1,440 minutes."
                return false
            }

            return await save(QuestionWriteOptions(recommendedDuration: newValue))
        }
        EditableLanguagesRow(value: displayed.languages) { newValue in
            await save(QuestionWriteOptions(languages: newValue ?? []))
        }
        EditableTextRow(
            label: "Skills",
            value: displayed.skills?.joined(separator: ", ") ?? "",
            prompt: "Comma-separated"
        ) { newValue in
            await save(QuestionWriteOptions(skills: splitList(newValue) ?? []))
        }
        EditableTextRow(
            label: "Tags",
            value: displayed.tags?.joined(separator: ", ") ?? "",
            prompt: "Comma-separated"
        ) { newValue in
            await save(QuestionWriteOptions(tags: splitList(newValue) ?? []))
        }
    }

    /// Testcase and code-stub actions for coding questions. HackerRank has no testcase read
    /// endpoint, so testcases can be added and bulk-deleted but not listed; per-testcase
    /// delete/update stay with the MCP tools, which take explicit testcase ids.
    private var codingSection: some View {
        Section("Testcases & code stubs") {
            Button {
                addTestcasePresented = true
            } label: {
                Label("Add Testcase…", systemImage: "plus.circle")
            }
            Button {
                generateStubsPresented = true
            } label: {
                Label("Generate Code Stubs…", systemImage: "wand.and.stars")
            }
            Button {
                customStubPresented = true
            } label: {
                Label("Set Custom Code Stub…", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Button(role: .destructive) {
                deleteTestcasesPresented = true
            } label: {
                Label("Delete All Testcases…", systemImage: "trash")
            }
        }
    }

    /// Applies one field's update (optionally a rename), keeps an optimistic local copy —
    /// the write echo and the detail read are both sparser than the list row, so the saved
    /// value is folded into the row model directly — and nudges the list to refresh.
    @discardableResult
    private func save(
        name: String? = nil,
        _ options: QuestionWriteOptions = QuestionWriteOptions()
    ) async -> Bool {
        guard let account = owningAccount else { return false }

        do {
            _ = try await HackerRankClient(account: account).updateQuestion(
                questionID: question.id,
                name: name,
                type: nil,
                options: options
            )
            editOverlay.merge(name: name, options: options)
            registerDetailCommands()
            onChanged()
            return true
        } catch {
            editError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    private func deleteAllTestcases() async {
        guard let account = owningAccount else { return }

        do {
            _ = try await HackerRankClient(account: account).deleteAllTestcases(questionID: question.id)
        } catch {
            editError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deleteQuestion() async {
        guard let account = owningAccount else { return }

        do {
            try await HackerRankClient(account: account).deleteQuestion(questionID: question.id)
            onChanged()
            dismiss()
        } catch {
            deleteError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Whether an option matches the (revealed) correct answer, so it can be ticked in the list.
    /// Only highlights once the answer has been revealed, keeping the answer hidden by default.
    private func isCorrect(_ option: String) -> Bool {
        answerRevealed && detail?.answer == option
    }

    private func registerDetailCommands() {
        commandContext.registerDetailActions(
            owner: commandOwner,
            print: AppCommandContext.Action(title: "Print Question…") {
                printReport(QuestionReport(data: reportData), jobTitle: "Question: \(displayed.name)")
            },
            exportMarkdown: AppCommandContext.Action(title: "Export Question as Markdown…") {
                let snapshot = reportData
                MarkdownExport.save(
                    { MarkdownExport.question(snapshot) },
                    suggestedName: snapshot.question.name
                )
            }
        )
    }

    /// Fetches the richer question detail on selection (#105). Best-effort — a failure leaves the
    /// base list-row detail intact — and skipped in the merged view, where the owning account is
    /// ambiguous, so the wrong account is never queried. Re-hides the answer for each question.
    private func loadDetail() async {
        detail = nil
        detailQuestion = nil
        answerRevealed = false
        guard let account = owningAccount else { return }

        let client = HackerRankClient(account: account)
        let metadataClient = HackerRankDetailMetadataClient(account: account)
        async let loadedDetail = try? client.question(id: question.id)
        async let loadedMetadata = try? metadataClient.question(id: question.id)

        detail = await loadedDetail
        detailQuestion = await (loadedMetadata).flatMap(\.self)?.applying(to: question)
    }
}

extension Question {
    /// A copy with a successful update's fields folded in, so the detail can display the
    /// saved state without a full list refresh (the write echo is only id/name/type).
    func applying(name: String?, _ options: QuestionWriteOptions) -> Question {
        Question(
            id: id,
            uniqueID: uniqueID,
            type: type,
            name: name ?? self.name,
            owner: owner,
            createdAt: createdAt,
            status: options.status ?? status,
            languages: options.languages ?? languages,
            problemStatement: options.problemStatement ?? problemStatement,
            recommendedDuration: options.recommendedDuration ?? recommendedDuration,
            tags: options.tags ?? tags,
            maxScore: options.maxScore ?? maxScore,
            skills: options.skills ?? skills
        )
    }
}
