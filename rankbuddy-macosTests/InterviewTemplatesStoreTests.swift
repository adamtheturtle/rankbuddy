//
//  InterviewTemplatesStoreTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

@MainActor
struct InterviewTemplatesStoreTests {
    /// An isolated, in-memory `UserDefaults` so tests never touch real templates.
    private func makeDefaults() -> UserDefaults {
        let suite = "test.interviewTemplates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func `adds and scopes by account`() {
        let store = InterviewTemplatesStore(isTesting: true)
        store.add(InterviewTemplate(accountID: "a", name: "Backend", kind: .quickPad))
        store.add(InterviewTemplate(accountID: "b", name: "Frontend", kind: .scheduled))

        #expect(store.templates(accountID: "a").map(\.name) == ["Backend"])
        #expect(store.templates(accountID: "b").map(\.name) == ["Frontend"])
    }

    @Test func `lists most recent first`() {
        let store = InterviewTemplatesStore(isTesting: true)
        store.add(InterviewTemplate(accountID: "a", name: "First", kind: .quickPad))
        store.add(InterviewTemplate(accountID: "a", name: "Second", kind: .quickPad))

        #expect(store.templates(accountID: "a").map(\.name) == ["Second", "First"])
    }

    @Test func `updates by ID`() {
        let store = InterviewTemplatesStore(isTesting: true)
        let template = InterviewTemplate(accountID: "a", name: "Old", kind: .quickPad)
        store.add(template)

        var edited = template
        edited.name = "New"
        edited.kind = .scheduled
        store.update(edited)

        let result = store.templates(accountID: "a")
        #expect(result.count == 1)
        #expect(result.first?.name == "New")
        #expect(result.first?.kind == .scheduled)
    }

    @Test func `update ignores unknown ID`() {
        let store = InterviewTemplatesStore(isTesting: true)
        store.add(InterviewTemplate(accountID: "a", name: "Keep", kind: .quickPad))
        store.update(InterviewTemplate(accountID: "a", name: "Ghost", kind: .quickPad, id: "missing"))

        #expect(store.templates(accountID: "a").map(\.name) == ["Keep"])
    }

    @Test func `removes by ID`() {
        let store = InterviewTemplatesStore(isTesting: true)
        let template = InterviewTemplate(accountID: "a", name: "Gone", kind: .quickPad)
        store.add(template)
        store.remove(id: template.id)

        #expect(store.templates(accountID: "a").isEmpty)
    }

    @Test func `prunes removed accounts`() {
        let store = InterviewTemplatesStore(isTesting: true)
        store.add(InterviewTemplate(accountID: "keep", name: "Stay", kind: .quickPad))
        store.add(InterviewTemplate(accountID: "drop", name: "Bye", kind: .quickPad))

        store.prune(toAccountIDs: ["keep"])

        #expect(store.templates.map(\.accountID) == ["keep"])
    }

    @Test func `persists across instances`() {
        let defaults = makeDefaults()
        let store = InterviewTemplatesStore(defaults: defaults)
        store.add(InterviewTemplate(accountID: "a", name: "Persisted", kind: .scheduled, titlePrefix: "Round 1"))

        let reloaded = InterviewTemplatesStore(defaults: defaults)
        let template = reloaded.templates(accountID: "a").first
        #expect(template?.name == "Persisted")
        #expect(template?.kind == .scheduled)
        #expect(template?.titlePrefix == "Round 1")
    }

    @Test func `on change fires for every mutation`() {
        let store = InterviewTemplatesStore(isTesting: true)
        var count = 0
        store.onChange = { count += 1 }

        let template = InterviewTemplate(accountID: "a", name: "T", kind: .quickPad)
        store.add(template)
        var edited = template
        edited.name = "Edited"
        store.update(edited)
        store.remove(id: template.id)

        #expect(count == 3)
    }

    @Test func `seeded title falls back to name`() {
        let blank = InterviewTemplate(accountID: "a", name: "Backend Screen", kind: .quickPad, titlePrefix: "  ")
        #expect(blank.seededTitle == "Backend Screen")

        let prefixed = InterviewTemplate(accountID: "a", name: "Backend", kind: .quickPad, titlePrefix: "Backend —")
        #expect(prefixed.seededTitle == "Backend —")
    }

    @Test func `undo restores template add edit and remove`() {
        let store = InterviewTemplatesStore(isTesting: true)
        let undoManager = UndoManager()
        let template = InterviewTemplate(accountID: "a", name: "Backend", kind: .quickPad)

        store.add(template, undoManager: undoManager)
        #expect(store.templates.count == 1)

        undoManager.undo()
        #expect(store.templates.isEmpty)

        undoManager.redo()
        #expect(store.templates.count == 1)

        var edited = template
        edited.name = "Frontend"
        store.update(edited, undoManager: undoManager)
        #expect(store.templates.first?.name == "Frontend")

        undoManager.undo()
        #expect(store.templates.first?.name == "Backend")

        store.remove(id: template.id, undoManager: undoManager)
        #expect(store.templates.isEmpty)

        undoManager.undo()
        #expect(store.templates.first?.id == template.id)
    }
}
