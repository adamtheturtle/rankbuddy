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
    @State private var isHovering = false
    @State private var isSaving = false
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
                .onChange(of: fieldFocused) { _, focused in
                    if !focused, isEditing { Task { await commit() } }
                }

            if isSaving {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func beginEditing() {
        guard editingAllowed else { return }

        draft = title
        isEditing = true
        fieldFocused = true
    }

    private func commit() async {
        guard isEditing, !isSaving else { return }
        guard let value = InlineEdit.commitValue(original: title, edited: draft) else {
            isEditing = false
            return
        }

        isSaving = true
        _ = await onCommit(value)
        isSaving = false
        isEditing = false
    }
}
