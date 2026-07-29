//
//  CommandEditableTitle.swift
//  rankbuddy-macos
//

import BuddyDesignSystem
import SwiftUI

/// Inline title editor that can also be opened by a toolbar or menu command. buddy-kit's
/// `InlineEditableTitle` owns its edit state privately, so it exposes no programmatic "begin
/// editing" hook — the detail pane's Edit button needs this app-side variant to make
/// Edit enter the same rename affordance a click on the title would (#95). Bumping `editRequest`
/// from the host begins editing; at `editRequest == 0` it behaves exactly like
/// `InlineEditableTitle`.
struct CommandEditableTitle: View {
    let title: String
    var placeholder: LocalizedStringKey = "Name"
    var isEditable = true
    var font: Font = .title2.weight(.semibold)
    /// The host increments this to open the editor from a command; each new value begins editing.
    var editRequest: Int
    /// Writes the new value, returning whether it succeeded; a failure reverts to the title.
    let onCommit: (String) async -> Bool

    @Environment(\.isReadOnly) private var isReadOnly
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isEditing = false
    @State private var draft = ""
    @State private var originalTitle = ""
    @State private var isHovering = false
    @State private var isSaving = false
    @State private var conflictMessage: String?
    @FocusState private var fieldFocused: Bool

    private var editingAllowed: Bool {
        isEditable && !isReadOnly
    }

    private var showsPencil: Bool {
        guard editingAllowed else { return false }

        #if os(macOS)
            return isHovering
        #else
            return true
        #endif
    }

    var body: some View {
        Group {
            if isEditing {
                editorField
            } else if editingAllowed {
                editableTitle
            } else {
                plainTitle
            }
        }
        .font(font)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: editRequest) { _, _ in beginEditing() }
        .alert("Title Changed", isPresented: conflictPresented) {
            Button("OK") { conflictMessage = nil }
        } message: {
            Text(conflictMessage ?? "")
        }
    }

    private var plainTitle: some View {
        Text(title)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editableTitle: some View {
        HStack(spacing: 6) {
            Text(title)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "pencil")
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(showsPencil ? 1 : 0)
                .touchTarget()
                .pointerHoverEffect()
                .accessibilityHidden(true)

            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.12), value: showsPencil)
        .onTapGesture { beginEditing() }
        .help("Click to rename")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Edit title")
    }

    private var editorField: some View {
        HStack(spacing: 8) {
            TextField(placeholder, text: $draft)
                .textFieldStyle(.plain)
                .focused($fieldFocused)
                .disabled(isSaving)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onSubmit { Task { await commit() } }
                .onExitCommand { cancelEditing() }
                .onChange(of: fieldFocused) { _, focused in
                    if !focused, isEditing { Task { await commit() } }
                }

            if isSaving {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func beginEditing() {
        guard editingAllowed, !isSaving else { return }

        originalTitle = title
        draft = title
        conflictMessage = nil
        isEditing = true
        fieldFocused = true
    }

    private var conflictPresented: Binding<Bool> {
        Binding(
            get: { conflictMessage != nil },
            set: { if !$0 { conflictMessage = nil } }
        )
    }

    /// Escape follows the Mac convention: restore the current title and leave edit mode without
    /// allowing the resulting focus loss to enter the commit path.
    private func cancelEditing() {
        guard isEditing, !isSaving else { return }

        draft = title
        isEditing = false
        fieldFocused = false
    }

    private func commit() async {
        guard isEditing, !isSaving else { return }
        guard let value = InlineEdit.commitValue(original: originalTitle, edited: draft) else {
            isEditing = false
            return
        }
        guard !Self.hasConflict(original: originalTitle, current: title) else {
            draft = title
            isEditing = false
            fieldFocused = false
            conflictMessage = """
            This title changed while you were editing. Your draft wasn’t saved. Review the current \
            title and try again.
            """
            return
        }

        isSaving = true
        _ = await onCommit(value)
        isSaving = false
        isEditing = false
    }

    nonisolated static func hasConflict(original: String, current: String) -> Bool {
        original != current
    }
}
