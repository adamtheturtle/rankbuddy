//
//  TestDetailView.swift
//  rankbuddy-macos
//

import BuddyAppKit
import HackerRankKit
import SwiftUI

/// Read-only detail for a single test, plus opt-in edit/delete affordances (#57). The
/// destructive delete is confirmed (naming the test) and pops back to the list on success.
///
/// Beyond the list row's fields, it fetches the richer single-test read on selection (#105) and
/// merges the candidate login links, the (sensitive) master password — gated behind an explicit
/// reveal — and the MCQ scoring. The fetch is best-effort: a failure leaves the list-row detail
/// intact.
struct TestDetailView: View {
    let test: Test
    let account: Account
    /// Called after a successful edit or delete so the list can refresh.
    var onChanged: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(AppCommandContext.self) private var commandContext
    /// Bumped by the Edit toolbar button to open the inline title rename (#95).
    @State private var titleEditRequest = 0
    @State private var deletePresented = false
    @State private var deleteError: String?
    @State private var detail: TestDetail?
    @State private var inviters: [TestInviter] = []
    @State private var passwordRevealed = false

    var body: some View {
        Form {
            InspectorHeader(
                title: test.name,
                badges: test.inspectorBadges(now: Date()),
                onRename: { newName in await rename(to: newName) },
                editRequest: titleEditRequest
            )

            Section("Properties") {
                OptionalRow("State", test.state?.capitalized)
                OptionalRow("Window", test.windowStatus(now: Date())?.label)
                OptionalRow("Unique ID", test.uniqueID)
                OptionalRow("Duration", test.duration.map { "\($0) min" })
                OptionalRow("Cutoff score", test.cutoffScore.map(String.init))
                OptionalRow("Questions", test.questions.map { "\($0.count)" })
                OptionalRow("Library", DisplayFormat.list(test.libraryFilterValues))
                OptionalRow("Role", DisplayFormat.list(test.roleFilterValues))
                OptionalRow("Skills", DisplayFormat.list(test.skillFilterValues))
                OptionalRow("Type", DisplayFormat.list(test.typeFilterValues))
                OptionalRow("Languages", DisplayFormat.languages(test.languages))
                OptionalRow("Proctoring", test.enableProctoring == true ? "Enabled" : nil)
                OptionalRow("Shuffle questions", test.shuffleQuestions == true ? "Yes" : nil)
                OptionalRow("Starred", test.starred == true ? "Yes" : nil)
                OptionalRow("Locked", test.locked == true ? "Yes" : nil)
                OptionalRow("Draft", test.draft == true ? "Yes" : nil)
                OptionalRow("MCQ correct score", detail?.mcqCorrectScore.map { $0.formatted() })
                OptionalRow("MCQ incorrect score", detail?.mcqIncorrectScore.map { $0.formatted() })
            }

            Section("Schedule") {
                OptionalRow("Starts", DisplayFormat.date(test.startTime))
                OptionalRow("Ends", DisplayFormat.date(test.endTime))
                OptionalRow("Created", DisplayFormat.date(test.createdAt))
            }

            if let detail, detail.hasAccess {
                accessSection(detail: detail)
            }

            if let sections = test.sections, !sections.isEmpty {
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

            if let tags = test.tags, !tags.isEmpty {
                Section("Tags") {
                    TagList(tags: tags)
                }
            }

            Section("Participants") {
                NavigationLink {
                    CandidatesList(testID: test.id, account: account)
                } label: {
                    Label("Candidates", systemImage: "person.2")
                }

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

            if let instructions = test.instructions, !instructions.isEmpty {
                Section("Instructions") {
                    HighlightedHTMLText(html: instructions)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(test.name)
        .task(id: test.id) { await loadDetail() }
        .onAppear { registerDetailCommands() }
        .onDisappear { commandContext.clearDetailActions() }
        .advertisesItemActivity(collection: .tests, itemID: test.id, title: test.name)
        // Share and Open (the test on HackerRank) lead the bar like PadBuddy; Edit and Delete
        // follow; Print and Markdown export are off by default but one Customize Toolbar away.
        .toolbar(id: "testDetail") {
            DetailLinkToolbarContent(
                url: RankBuddyUserActivity.webURL(base: account.baseURL, collection: .tests, itemID: test.id),
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
            ToolbarItem(id: "delete") {
                Button(role: .destructive) {
                    deletePresented = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete this test")
            }
            ToolbarItem(id: "print") {
                PrintReportButton(jobTitle: "Test: \(test.name)") {
                    TestReport(test: test)
                }
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "exportMarkdown") {
                MarkdownExportButton(suggestedName: test.name) { MarkdownExport.test(test) }
            }
            .defaultCustomization(.hidden)
        }
        .confirmationDialog("Delete “\(test.name)”?", isPresented: $deletePresented, titleVisibility: .visible) {
            Button("Delete Test", role: .destructive) {
                Task { await delete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(account.isMock
                ? "Demo account: no real test is deleted."
                : "This permanently deletes the test on HackerRank. This can’t be undone.")
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
            if let short = detail.shortLoginURL, let url = URL(string: short) {
                Link(destination: url) {
                    Label("Short login link", systemImage: "link")
                }
            }
            if let publicURL = detail.publicLoginURL, let url = URL(string: publicURL) {
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

    private func registerDetailCommands() {
        commandContext.print = AppCommandContext.Action(title: "Print Test…") {
            printReport(TestReport(test: test), jobTitle: "Test: \(test.name)")
        }
        commandContext.exportMarkdown = AppCommandContext.Action(title: "Export Test as Markdown…") {
            MarkdownExport.save(MarkdownExport.test(test), suggestedName: test.name)
        }
    }

    /// Fetches the richer test detail on selection (#105). Best-effort, and re-hides the master
    /// password for each test.
    private func loadDetail() async {
        detail = nil
        inviters = []
        passwordRevealed = false
        let client = HackerRankClient(account: account)
        async let loadedDetail = try? client.test(id: test.id)
        async let loadedInviters = try? client.testInviters(testID: test.id)

        detail = await loadedDetail
        inviters = await (loadedInviters)?.items ?? []
    }

    private func delete() async {
        do {
            try await HackerRankClient(account: account).deleteTest(testID: test.id)
            onChanged()
            dismiss()
        } catch {
            deleteError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Commits an inline rename of the test (#95), reusing the same write the editor sheet uses.
    /// Returns whether it succeeded so the inline title can revert on failure; on success the
    /// list refreshes (which re-pushes the renamed detail).
    private func rename(to newName: String) async -> Bool {
        do {
            try await HackerRankClient(account: account).updateTest(testID: test.id, name: newName)
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
