//
//  QuestionDetailView.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

// swiftlint:disable file_length

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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppCommandContext.self) private var commandContext
    @State var detail: QuestionDetail?
    @State private var detailError: String?
    @State private var isDetailLoading = false
    @State var answerRevealed = false
    @State private var deletePresented = false
    @State private var deleteError: String?
    @State private var isDeletingQuestion = false
    @State var editError: String?
    @State private var detailQuestion: Question?
    /// Local field overlay for saved edits; fresh server metadata remains the underlying model.
    @State private var editOverlay = QuestionEditOverlay()
    @State private var addTestcasePresented = false
    @State private var deleteTestcasesPresented = false
    @State private var isDeletingTestcases = false
    @State private var generateStubsPresented = false
    @State private var customStubPresented = false
    @State private var commandOwner = UUID()
    @State var selectedPane: QuestionDetailPane = .overview

    init(question: Question, account: Account? = nil, onChanged: @escaping () -> Void = {}) {
        self.question = question
        self.account = account
        self.onChanged = onChanged
    }

    private var owningAccount: Account? {
        account ?? (store.isMergedView ? nil : store.currentAccount)
    }

    private var requestIdentity: QuestionDetailRequestIdentity {
        QuestionDetailRequestIdentity(accountID: owningAccount?.id, questionID: question.id)
    }

    /// The freshest copy of the question: saved edits overlay the detail metadata, then the list row.
    var displayed: Question {
        editOverlay.applying(to: detailQuestion ?? question)
    }

    private var reportData: QuestionReportData {
        QuestionReportData(question: displayed, detail: detail, includeCorrectAnswer: answerRevealed)
    }

    /// Editing needs a single owning account, so the merged view stays read-only.
    var canEdit: Bool {
        owningAccount != nil
    }

    private var availablePanes: [QuestionDetailPane] {
        var panes: [QuestionDetailPane] = [.overview, .content, .guidelines, .answer]
        if canEdit, displayed.type.lowercased() == "coding" {
            panes.append(.coding)
        }
        return panes
    }

    /// The problem statement, or `nil` when it is missing or renders as blank — HackerRank
    /// sometimes stores markup like `<p><br></p>` with no visible text, which would otherwise
    /// pass a plain emptiness check and show as an empty box.
    var problemStatement: String? {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                InspectorHeader(title: displayed.name, badges: displayed.inspectorBadges, onRename: renameAction)
                Divider()

                detailLoadStatus

                selectedPaneContent
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            QuestionDetailPaneBar(panes: availablePanes, selection: selectedPane) { pane in
                selectedPane = pane
            }
        }
        .navigationTitle(displayed.name)
        .nativeResourceActions(.question, account: owningAccount, path: ["question_id": question.id]) {
            onChanged()
            Task { await loadDetail(for: requestIdentity) }
        }
        .task(id: requestIdentity) { await loadDetail(for: requestIdentity) }
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
        .onChange(of: selectedPane) {
            if selectedPane != .answer {
                answerRevealed = false
            }
        }
        .onDisappear {
            answerRevealed = false
            commandContext.clearDetailActions(owner: commandOwner)
        }
        .advertisesItemActivity(
            collection: .questions,
            itemID: question.id,
            title: displayed.name,
            account: owningAccount
        )
        // Share and Open stay in the bar; Print and Markdown export are off the bar by default but
        // one Customize Toolbar away.
        .windowToolbar(id: "questionDetail") {
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
                .disabled(owningAccount == nil || isDeletingQuestion)
            }
            .defaultCustomization(.hidden)
        }
        .confirmationDialog("Delete “\(displayed.name)”?", isPresented: $deletePresented, titleVisibility: .visible) {
            Button("Delete Question", role: .destructive) {
                Task { await deleteQuestion() }
            }
            .disabled(isDeletingQuestion)
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
            .disabled(isDeletingTestcases)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes every testcase from “\(displayed.name)” on HackerRank. This can’t be undone.")
        }
    }

    @ViewBuilder private var detailLoadStatus: some View {
        if isDetailLoading {
            ProgressView("Loading question details…")
        } else if let detailError {
            VStack(alignment: .leading, spacing: 8) {
                Label(detailError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Button("Retry Details") {
                    Task { await loadDetail(for: requestIdentity) }
                }
            }
        }
    }
}

// MARK: - Editing, destructive actions, and detail loading

extension QuestionDetailView {
    private var deleteErrorPresented: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: {
            if !$0 {
                deleteError = nil
            }
        })
    }

    private var editErrorPresented: Binding<Bool> {
        Binding(get: { editError != nil }, set: {
            if !$0 {
                editError = nil
            }
        })
    }

    /// Testcase and code-stub actions for coding questions. HackerRank has no testcase read
    /// endpoint, so testcases can be added and bulk-deleted but not listed; per-testcase
    /// delete/update stay with the MCP tools, which take explicit testcase ids.
    var codingSection: some View {
        QuestionDetailSection("Testcases & code stubs") {
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
            .disabled(isDeletingTestcases)
        }
    }

    /// Applies one field's update (optionally a rename), keeps an optimistic local copy —
    /// the write echo and the detail read are both sparser than the list row, so the saved
    /// value is folded into the row model directly — and nudges the list to refresh.
    @discardableResult
    func save(
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
        guard !isDeletingTestcases, let account = owningAccount else { return }

        isDeletingTestcases = true
        defer { isDeletingTestcases = false }

        do {
            _ = try await HackerRankClient(account: account).deleteAllTestcases(questionID: question.id)
        } catch {
            editError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func deleteQuestion() async {
        guard !isDeletingQuestion else { return }

        isDeletingQuestion = true
        defer { isDeletingQuestion = false }

        deleteError = "HackerRank no longer exposes an API to delete questions."
    }

    /// Whether an option matches the (revealed) correct answer, so it can be ticked in the list.
    /// Only highlights once the answer has been revealed, keeping the answer hidden by default.
    func isCorrect(_ option: String) -> Bool {
        guard answerRevealed,
              let answer = detail?.answer,
              let options = detail?.options,
              let index = options.firstIndex(of: option) else { return false }

        return answer.indices.contains(index + 1)
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
    private func loadDetail(for identity: QuestionDetailRequestIdentity) async {
        selectedPane = .overview
        detail = nil
        detailError = nil
        isDetailLoading = true
        detailQuestion = nil
        editOverlay = QuestionEditOverlay()
        answerRevealed = false
        guard let account = owningAccount else {
            isDetailLoading = false
            return
        }

        let client = HackerRankClient(account: account)
        let metadataClient = HackerRankDetailMetadataClient(account: account)
        async let loadedDetail = Self.fetchDetail(client: client, questionID: question.id)
        async let loadedMetadata = try? metadataClient.question(id: question.id)
        let loaded = await (loadedDetail, loadedMetadata)
        guard !Task.isCancelled, identity == requestIdentity else { return }

        isDetailLoading = false
        switch loaded.0 {
        case let .loaded(value):
            detail = value
        case let .failed(message):
            detailError = message
        }
        detailQuestion = loaded.1?.applying(to: question)
    }

    private enum DetailLoadResult {
        case loaded(QuestionDetail)
        case failed(String)
    }

    private nonisolated static func fetchDetail(
        client: HackerRankClient,
        questionID: String
    ) async -> DetailLoadResult {
        do {
            return try await .loaded(client.question(id: questionID))
        } catch {
            return .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
