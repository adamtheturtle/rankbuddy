//
//  InterviewTemplatesView.swift
//  rankbuddy-macos
//

import SwiftUI

/// Manages an account's saved interview templates (#97): a master/detail sheet listing the
/// account's templates with a segmented add/remove control and an inline editor, mirroring the
/// Accounts settings layout (#71). Read-only config — running a template happens elsewhere.
struct InterviewTemplatesView: View {
    let accountID: String
    @Bindable var store: InterviewTemplatesStore

    @Environment(\.dismiss) private var dismiss
    @State private var selection: String?

    private var templates: [InterviewTemplate] {
        store.templates(accountID: accountID)
    }

    var body: some View {
        NavigationStack {
            HSplitView {
                sidebar
                    .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
                editor
                    .frame(minWidth: 280)
            }
            .navigationTitle("Interview Templates")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(width: 600, height: 380)
        .onAppear { if selection == nil { selection = templates.first?.id } }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(templates) { template in
                    Label(template.name, systemImage: template.kind.systemImage)
                        .lineLimit(1)
                        .tag(template.id)
                }
            }
            .overlay {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No Templates",
                        systemImage: "rectangle.stack.badge.plus",
                        description: Text("Add a template to launch a recurring interview in one action.")
                    )
                }
            }

            Divider()
            controlBar
        }
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            Button { addTemplate() } label: {
                Image(systemName: "plus").frame(width: 24, height: 20)
                    .accessibilityLabel("Add a template")
            }
            .help("Add a template")

            Button { removeSelected() } label: {
                Image(systemName: "minus").frame(width: 24, height: 20)
                    .accessibilityLabel("Remove the selected template")
            }
            .help("Remove the selected template")
            .disabled(selection == nil)

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(4)
    }

    @ViewBuilder private var editor: some View {
        if let id = selection, let template = templates.first(where: { $0.id == id }) {
            TemplateEditor(template: template) { store.update($0) }
                .id(id)
        } else {
            ContentUnavailableView(
                "Select a Template",
                systemImage: "sidebar.left",
                description: Text("Choose a template to edit, or add a new one.")
            )
        }
    }

    private func addTemplate() {
        let template = InterviewTemplate(accountID: accountID, name: "New Template", kind: .quickPad)
        store.add(template)
        selection = template.id
    }

    private func removeSelected() {
        guard let id = selection else { return }

        store.remove(id: id)
        selection = templates.first?.id
    }
}

/// The inline editor for one template's fields, committing edits to the store on change.
private struct TemplateEditor: View {
    let template: InterviewTemplate
    var onCommit: (InterviewTemplate) -> Void

    @State private var name: String
    @State private var kind: InterviewTemplateKind
    @State private var titlePrefix: String

    init(template: InterviewTemplate, onCommit: @escaping (InterviewTemplate) -> Void) {
        self.template = template
        self.onCommit = onCommit
        _name = State(initialValue: template.name)
        _kind = State(initialValue: template.kind)
        _titlePrefix = State(initialValue: template.titlePrefix)
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                Picker("Kind", selection: $kind) {
                    ForEach(InterviewTemplateKind.allCases, id: \.self) { kind in
                        Label(kind.label, systemImage: kind.systemImage).tag(kind)
                    }
                }
                TextField("Title prefix (optional)", text: $titlePrefix)
            } footer: {
                Text("Running this template opens the \(kind.label) form pre-filled with the title prefix.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .onChange(of: name) { commit() }
        .onChange(of: kind) { commit() }
        .onChange(of: titlePrefix) { commit() }
    }

    private func commit() {
        var edited = template
        edited.name = name
        edited.kind = kind
        edited.titlePrefix = titlePrefix
        onCommit(edited)
    }
}

#Preview {
    let store = InterviewTemplatesStore(isTesting: true)
    store.add(InterviewTemplate(accountID: "a", name: "Senior Backend", kind: .quickPad, titlePrefix: "Backend —"))
    store.add(InterviewTemplate(accountID: "a", name: "Live SQL Screen", kind: .scheduled, titlePrefix: "SQL"))
    return InterviewTemplatesView(accountID: "a", store: store)
}
