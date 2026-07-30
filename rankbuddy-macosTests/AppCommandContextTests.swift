//
//  AppCommandContextTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

@MainActor
struct AppCommandContextTests {
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
}
