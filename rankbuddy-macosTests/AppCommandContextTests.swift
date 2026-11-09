//
//  AppCommandContextTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

@MainActor
struct AppCommandContextTests {
    @Test func `filter reset follows the active list and clears when lists close`() {
        let context = AppCommandContext()
        let mainOwner = UUID()
        let secondOwner = UUID()
        let recorder = FilterResetRecorder()
        context.registerListActions(owner: mainOwner, actions: .init(
            primaryNew: nil, secondaryNew: nil, exportCSV: nil, exportSelectedCSV: nil,
            refresh: .init(title: "Refresh Main") {},
            resetFilters: .init(title: "Reset Main") { recorder.owners.append(mainOwner) }
        ))
        context.registerListActions(owner: secondOwner, actions: .init(
            primaryNew: nil, secondaryNew: nil, exportCSV: nil, exportSelectedCSV: nil,
            refresh: .init(title: "Refresh Second") {},
            resetFilters: .init(title: "Reset Second") { recorder.owners.append(secondOwner) }
        ))
        context.activateListActions(owner: secondOwner)
        context.resetFilters?.perform()
        context.deactivateListActions(owner: secondOwner)
        #expect(context.resetFilters == nil)
        context.activateListActions(owner: mainOwner)
        context.resetFilters?.perform()
        context.activateListActions(owner: secondOwner)
        context.clearListActions(owner: mainOwner)
        context.resetFilters?.perform()
        #expect(recorder.owners == [secondOwner, mainOwner, secondOwner])
        context.clearListActions(owner: secondOwner)
        #expect(context.resetFilters == nil)
    }

    @Test func `removing one detail owner restores the previous commands`() {
        let context = AppCommandContext()
        let mainOwner = UUID()
        let windowOwner = UUID()

        context.registerDetailActions(
            owner: mainOwner,
            print: .init(title: "Print Main") {},
            exportMarkdown: .init(title: "Export Main") {}
        )
        context.registerDetailActions(
            owner: windowOwner,
            print: .init(title: "Print Window") {},
            exportMarkdown: .init(title: "Export Window") {}
        )

        #expect(context.print?.title == "Print Window")
        context.clearDetailActions(owner: windowOwner)
        #expect(context.print?.title == "Print Main")
        #expect(context.exportMarkdown?.title == "Export Main")
    }

    @Test func `removing a background owner preserves the active commands`() {
        let context = AppCommandContext()
        let mainOwner = UUID()
        let windowOwner = UUID()

        context.registerDetailActions(
            owner: mainOwner,
            print: .init(title: "Print Main") {},
            exportMarkdown: .init(title: "Export Main") {}
        )
        context.registerDetailActions(
            owner: windowOwner,
            print: .init(title: "Print Window") {},
            exportMarkdown: .init(title: "Export Window") {}
        )

        context.clearDetailActions(owner: mainOwner)
        #expect(context.print?.title == "Print Window")
        #expect(context.exportMarkdown?.title == "Export Window")
    }

    @Test func `activating a window owner switches the commands to that window`() {
        let context = AppCommandContext()
        let mainOwner = UUID()
        let windowOwner = UUID()

        context.registerDetailActions(
            owner: mainOwner,
            print: .init(title: "Print Main") {},
            exportMarkdown: .init(title: "Export Main") {}
        )
        context.registerDetailActions(
            owner: windowOwner,
            print: .init(title: "Print Window") {},
            exportMarkdown: .init(title: "Export Window") {}
        )

        context.activateDetailActions(owner: mainOwner)
        #expect(context.print?.title == "Print Main")
        context.activateDetailActions(owner: windowOwner)
        #expect(context.print?.title == "Print Window")
    }
}

@MainActor private final class FilterResetRecorder {
    var owners: [UUID] = []
}
