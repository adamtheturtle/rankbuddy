//
//  TestDetailView.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

// Read-only detail for a single test, plus opt-in edit/delete affordances (#57). The
// destructive delete is confirmed (naming the test) and pops back to the list on success.
//
// Beyond the list row's fields, it fetches the richer single-test read on selection (#105) and
// merges the candidate login links, the (sensitive) master password — gated behind an explicit
// reveal — and the MCQ scoring. The fetch is best-effort: a failure leaves the list-row detail
// intact.
// swiftlint:disable:next type_body_length
struct TestDetailView: View {
    let test: Test
    let account: Account
    /// Called after a successful edit or delete so the list can refresh.
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppCommandContext.self) private var commandContext
    /// Bumped by the Edit toolbar button to open the inline title rename (#95).
    @State private var titleEditRequest = 0
    @State private var archivePresented = false
    @State private var archiveError: String?
    @State private var deletePresented = false
    @State private var deleteError: String?
    @State private var isDeleting = false
    @State private var detail: TestDetail?
    @State private var detailTest: Test?
    @State private var inviters: [TestInviter] = []
    @State private var passwordRevealed = false

    private var displayedTest: Test {
        detailTest ?? test
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Form {
                InspectorHeader(
                    title: displayedTest.name,
                    badges: displayedTest.inspectorBadges(now: context.date),
                    onRename: { newName in await rename(to: newName) },
                    editRequest: titleEditRequest
                )

                Section("Properties") {
                    OptionalRow("State", DisplayFormat.enumLabel(displayedTest.state))
                    OptionalRow("Window", displayedTest.windowStatus(now: context.date)?.label)
                    OptionalRow("Unique ID", displayedTest.uniqueID)
                    OptionalRow("Duration", displayedTest.duration.map { "\($0) min" })
                    OptionalRow("Cutoff score", displayedTest.cutoffScore.map(String.init))
                    OptionalRow("Questions", displayedTest.questions.map { "\($0.count)" })
                    OptionalRow("Library", DisplayFormat.list(displayedTest.libraryFilterValues))
                    OptionalRow("Role", DisplayFormat.list(displayedTest.roleFilterValues))
                    OptionalRow("Skills", DisplayFormat.list(displayedTest.skillFilterValues))
                    OptionalRow("Type", DisplayFormat.list(displayedTest.typeFilterValues))
                    OptionalRow("Languages", DisplayFormat.languages(displayedTest.languages))
                    OptionalRow(
                        "Proctoring",
                        DisplayFormat.boolean(
                            displayedTest.enableProctoring,
                            trueLabel: "Enabled",
                            falseLabel: "Disabled"
                        )
                    )
                    OptionalRow("Shuffle questions", DisplayFormat.boolean(displayedTest.shuffleQuestions))
                    OptionalRow("Starred", DisplayFormat.boolean(displayedTest.starred))
                    OptionalRow("Locked", DisplayFormat.boolean(displayedTest.locked))
                    OptionalRow("Draft", DisplayFormat.boolean(displayedTest.draft))
                    OptionalRow("MCQ correct score", detail?.mcqCorrectScore.map { $0.formatted() })
                    OptionalRow("MCQ incorrect score", detail?.mcqIncorrectScore.map { $0.formatted() })
                }

                Section("Schedule") {
                    OptionalRow("Starts", DisplayFormat.date(displayedTest.startTime))
                    OptionalRow("Ends", DisplayFormat.date(displayedTest.endTime))
                    OptionalRow("Created", DisplayFormat.date(displayedTest.createdAt))
                }

                if let detail, detail.hasAccess {
                    accessSection(detail: detail)
                }

                if let sections = displayedTest.sections, !sections.isEmpty {
                    Section("Sections") {
                        ForEach(sections) { section in
                            LabeledContent(section.displayName) {
                                if let count = section.questionCount {
                                    Text("\(count) question\(count == 1 ? "" : "s")")
                                }
                            }
                        }
                    }
                }

                if let tags = displayedTest.tags, !tags.isEmpty {
                    Section("Tags") {
                        TagList(tags: tags)
                    }
                }

                Section("Participants") {
                    WindowLinkRow(
                        title: "Candidates",
                        systemImage: "person.2",
                        value: .testCandidates(
                            testID: displayedTest.id,
                            testName: displayedTest.name,
                            accountID: account.id
                        )
                    )

                    if !inviters.isEmpty {
                        ForEach(inviters) { inviter in
                            LabeledContent(inviter.displayName) {
                                VStack(alignment: .trailing, spacing: 2) {
                                    if !inviter.email.isEmpty {
                                        Text(inviter.email)
                                    }
                                    if let role = inviter.role, !role.isEmpty {
                                        Text(role)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .textSelection(.enabled)
                            }
                        }
                    }
                }

                if let instructions = displayedTest.instructions, !instructions.isEmpty {
                    Section("Instructions") {
                        HighlightedHTMLText(html: instructions)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(displayedTest.name)
        .task(id: displayedTest.id) { await loadDetail() }
        .onAppear { registerDetailCommands() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                passwordRevealed = false
            }
        }
        .onDisappear {
            passwordRevealed = false
            commandContext.clearDetailActions()
        }
        .advertisesItemActivity(collection: .tests, itemID: displayedTest.id, title: displayedTest.name)
        // Share and Open (the test on HackerRank) lead the bar like PadBuddy; Edit and Delete
        // follow; Print and Markdown export are off by default but one Customize Toolbar away.
        .toolbar(id: "testDetail") {
            DetailLinkToolbarContent(
                url: RankBuddyUserActivity.webURL(base: account.baseURL, collection: .tests, itemID: displayedTest.id),
                noun: "test"
            )
            ToolbarItem(id: "edit") {
                Button {
                    titleEditRequest += 1
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .help("Rename this test")
            }
            ToolbarItem(id: "archive") {
                Button {
                    archivePresented = true
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .help("Archive this test")
                .disabled(displayedTest.state?.localizedCaseInsensitiveCompare("archived") == .orderedSame)
            }
            ToolbarItem(id: "delete") {
                Button(role: .destructive) {
                    deletePresented = true
                } label: {
                    if isDeleting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .help("Delete this test")
                .disabled(isDeleting)
            }
            ToolbarItem(id: "print") {
                PrintReportButton(jobTitle: "Test: \(displayedTest.name)") {
                    TestReport(test: displayedTest)
                }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "exportMarkdown") {
                let snapshot = displayedTest
                MarkdownExportButton(suggestedName: snapshot.name) {
                    MarkdownExport.test(snapshot)
                }
            }
            .defaultCustomization(.hidden)
        }
        .confirmationDialog(
            "Archive “\(displayedTest.name)”?",
            isPresented: $archivePresented,
            titleVisibility: .visible
        ) {
            Button("Archive Test") {
                Task { await archive() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This archives the test on HackerRank.")
        }
        .alert("Couldn’t archive test", isPresented: archiveErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(archiveError ?? "")
        }
        .confirmationDialog(
            "Delete “\(displayedTest.name)”?",
            isPresented: $deletePresented,
            titleVisibility: .visible
        ) {
            Button("Delete Test", role: .destructive) {
                beginDelete()
            }
            .disabled(isDeleting)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the test on HackerRank. This can’t be undone.")
        }
        .alert("Couldn’t delete test", isPresented: deleteErrorPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }

    /// Candidate login links and the (sensitive) shared access password, gated behind a reveal.
    private func accessSection(detail: TestDetail) -> some View {
        Section("Access") {
            if let short = detail.shortLoginURL, let url = URL.remoteWebURL(from: short) {
                Link(destination: url) {
                    Label("Short login link", systemImage: "link")
                }
            }
            if let publicURL = detail.publicLoginURL, let url = URL.remoteWebURL(from: publicURL) {
                Link(destination: url) {
                    Label("Public login link", systemImage: "globe")
                }
            }
            if let password = detail.accessPassword, !password.isEmpty {
                if passwordRevealed {
                    LabeledContent("Access password") {
                        Text(password).textSelection(.enabled)
                    }
                } else {
                    Button {
                        passwordRevealed = true
                    } label: {
                        Label("Reveal access password", systemImage: "eye")
                    }
                    .help("Show the test's shared access password")
                }
            }
        }
    }

    private var deleteErrorPresented: Binding<Bool> {
        Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })
    }

    private var archiveErrorPresented: Binding<Bool> {
        Binding(get: { archiveError != nil }, set: { if !$0 { archiveError = nil } })
    }

    private func registerDetailCommands() {
        commandContext.print = AppCommandContext.Action(title: "Print Test…") {
            printReport(TestReport(test: displayedTest), jobTitle: "Test: \(displayedTest.name)")
        }
        commandContext.exportMarkdown = AppCommandContext.Action(title: "Export Test as Markdown…") {
            let test = displayedTest
            MarkdownExport.save({ MarkdownExport.test(test) }, suggestedName: test.name)
        }
    }

    /// Fetches the richer test detail on selection (#105). Best-effort, and re-hides the master
    /// password for each test.
    private func loadDetail() async {
        detail = nil
        detailTest = nil
        inviters = []
        passwordRevealed = false
        let client = HackerRankClient(account: account)
        let metadataClient = HackerRankDetailMetadataClient(account: account)
        async let loadedDetail = try? client.test(id: test.id)
        async let loadedInviters = try? client.testInviters(testID: test.id)
        async let loadedMetadata = try? metadataClient.test(id: test.id)

        detail = await loadedDetail
        detailTest = await (loadedMetadata).flatMap(\.self)?.applying(to: test)
        inviters = await (loadedInviters)?.items ?? []
    }

    private func beginDelete() {
        guard !isDeleting else { return }

        isDeleting = true
        Task { await delete() }
    }

    private func delete() async {
        defer { isDeleting = false }
        do {
            try await HackerRankClient(account: account).deleteTest(testID: displayedTest.id)
            onChanged()
            dismiss()
        } catch {
            deleteError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func archive() async {
        do {
            try await HackerRankClient(account: account).archiveTest(testID: displayedTest.id)
            onChanged()
            dismiss()
        } catch {
            archiveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Commits an inline rename of the test (#95), reusing the same write the editor sheet uses.
    /// Returns whether it succeeded so the inline title can revert on failure; on success the
    /// list refreshes (which re-pushes the renamed detail).
    private func rename(to newName: String) async -> Bool {
        let normalizedName = TestNameValidation.normalized(newName)
        guard TestNameValidation.isValid(normalizedName) else { return false }
        guard TestNameValidation.canSubmit(normalizedName, currentName: displayedTest.name) else { return true }

        do {
            try await HackerRankClient(account: account).updateTest(testID: displayedTest.id, name: normalizedName)
            var renamed = TestDetailMetadata()
            renamed.name = normalizedName
            detailTest = renamed.applying(to: displayedTest)
            onChanged()
            return true
        } catch {
            return false
        }
    }
}

private extension TestInviter {
    var displayName: String {
        let fullName = [firstName, lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if !fullName.isEmpty {
            return fullName
        }
        if !email.isEmpty {
            return email
        }
        return id
    }
}

#Preview("Detail") {
    let json = #"""
    {"id":"t1","unique_id":"backend-screen","name":"Backend Engineer Screen","state":"active",
     "duration":90,"cutoff_score":70,"enable_proctoring":true,"languages":["python","go"],
     "shuffle_questions":true,"starred":true,
     "start_time":"2026-01-01T09:00:00Z","end_time":"2026-12-31T09:00:00Z","questions":["q1","q2"],
     "tags":["backend"],
     "sections":[{"uuid":"s1","name":"Coding","questions":2,"duration":60},
                 {"uuid":"s2","name":"Multiple Choice","questions":5,"duration":30}]}
    """#
    let test = try? JSONDecoder().decode(Test.self, from: Data(json.utf8))
    return NavigationStack {
        if let test {
            TestDetailView(test: test, account: Account(label: "Demo", token: "demo"))
        }
    }
}
