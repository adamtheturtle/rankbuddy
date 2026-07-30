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

    private struct DetailRegistration {
        let owner: UUID
        let print: Action
        let exportMarkdown: Action
    }

    var primaryNew: Action?
    var secondaryNew: Action?
    var exportCSV: Action?
    var exportSelectedCSV: Action?
    var exportMarkdown: Action?
    var print: Action?
    private var detailRegistrations: [DetailRegistration] = []
    /// Reloads the visible list (⌘R). Mirrors PadBuddy, whose Reload lives on the Go menu so the
    /// toolbar's Refresh button can be hidden from the default toolbar (#101).
    var refresh: Action?

    func clearListActions() {
        primaryNew = nil
        secondaryNew = nil
        exportCSV = nil
        exportSelectedCSV = nil
        refresh = nil
    }

    func registerDetailActions(owner: UUID, print: Action, exportMarkdown: Action) {
        if let index = detailRegistrations.firstIndex(where: { $0.owner == owner }) {
            detailRegistrations[index] = DetailRegistration(
                owner: owner,
                print: print,
                exportMarkdown: exportMarkdown
            )
            if index == detailRegistrations.indices.last {
                applyTopDetailRegistration()
            }
        } else {
            detailRegistrations.append(DetailRegistration(
                owner: owner,
                print: print,
                exportMarkdown: exportMarkdown
            ))
            applyTopDetailRegistration()
        }
    }

    func clearDetailActions(owner: UUID) {
        detailRegistrations.removeAll { $0.owner == owner }
        applyTopDetailRegistration()
    }

    func activateDetailActions(owner: UUID) {
        guard let index = detailRegistrations.firstIndex(where: { $0.owner == owner }) else { return }

        let registration = detailRegistrations.remove(at: index)
        detailRegistrations.append(registration)
        applyTopDetailRegistration()
    }

    private func applyTopDetailRegistration() {
        exportMarkdown = detailRegistrations.last?.exportMarkdown
        print = detailRegistrations.last?.print
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

private struct DetailCommandActivationModifier: ViewModifier {
    let context: AppCommandContext
    let owner: UUID
    @Environment(\.controlActiveState) private var controlActiveState

    func body(content: Content) -> some View {
        content.onChange(of: controlActiveState) { _, state in
            if state == .key {
                context.activateDetailActions(owner: owner)
            }
        }
    }
}

extension View {
    func activatesDetailCommands(in context: AppCommandContext, owner: UUID) -> some View {
        modifier(DetailCommandActivationModifier(context: context, owner: owner))
    }
}
