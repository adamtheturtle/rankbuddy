//
//  AppCommandContext.swift
//  rankbuddy-macos
//

import SwiftUI

/// The active view's menu-addressable actions. Views register while they are visible so
/// app-level commands can mirror toolbar/context-menu functionality without owning list state.
@Observable
@MainActor
final class AppCommandContext {
    struct Action {
        let title: String
        var isEnabled: @MainActor () -> Bool = { true }
        let perform: @MainActor () -> Void
    }

    var primaryNew: Action?
    var secondaryNew: Action?
    var exportCSV: Action?
    var exportSelectedCSV: Action?
    var exportMarkdown: Action?
    var print: Action?

    func clearListActions() {
        primaryNew = nil
        secondaryNew = nil
        exportCSV = nil
        exportSelectedCSV = nil
    }

    func clearDetailActions() {
        exportMarkdown = nil
        print = nil
    }
}

struct CommandActionButton: View {
    let action: AppCommandContext.Action?
    let fallbackTitle: String

    var body: some View {
        Button(action?.title ?? fallbackTitle) {
            action?.perform()
        }
        .disabled(action?.isEnabled() != true)
    }
}
