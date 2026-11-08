//
//  NativeFeatureFormSheet.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

struct NativeFeatureFormSheet: View {
    let title: String
    let account: Account
    let onSaved: () -> Void
    let embedded: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var model: NativeFeatureFormModel?
    @State private var loading = false
    @State private var confirmDeletion = false
    private let setupError: String?

    init(title: String, operationID: String, account: Account, path: [String: String] = [:],
         initial: HackerRankJSONValue? = nil, embedded: Bool = false, onSaved: @escaping () -> Void = {}) {
        self.title = title
        self.embedded = embedded
        self.account = account
        self.onSaved = onSaved
        do {
            _model = try State(initialValue: NativeFeatureFormModel(
                operationID: operationID,
                path: path,
                initial: initial
            ))
            setupError = nil
        } catch { setupError = error.localizedDescription }
    }

    var body: some View {
        presentation
            .environment(\.nativeFeatureAccount, account)
            .environment(\.nativeFormOmissionLabel,
                         model?.operation.method == "PUT" && model?.operation.scim == false ? "Unchanged" : "Default")
            .interactiveDismissDisabled(model?.sending == true)
            .confirmationDialog(title, isPresented: $confirmDeletion, titleVisibility: .visible) {
                Button("Confirm Deletion", role: .destructive) {
                    if let model {
                        submit(model)
                    }
                }
            } message: { Text("This changes data in \(account.label). This action cannot be undone in RankBuddy.") }
            .task { await loadExisting() }
    }

    @ViewBuilder private var presentation: some View {
        if embedded {
            form
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if let model {
                        HStack {
                            Spacer()
                            submitButton(model).buttonStyle(.borderedProminent)
                        }
                        .padding(16).background(.bar)
                    }
                }
        } else {
            NavigationStack {
                form
                    .navigationTitle(title)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(dismissTitle) { dismiss() }.disabled(model?.sending == true)
                        }
                        if let model {
                            ToolbarItem(placement: .confirmationAction) { submitButton(model) }
                        }
                    }
            }
            .frame(minWidth: 640, idealWidth: 680, minHeight: 500, idealHeight: 650)
        }
    }

    private var form: some View {
        Form {
            if !embedded {
                LabeledContent("Account", value: account.label)
            }
            if let model {
                if model.operation.scim, account.scimToken?.isEmpty != false, !account.isMock {
                    Text("Add this account’s provisioning token in Account Settings to manage provisioning.")
                    SettingsLink { Text("Account Settings") }
                }
                ForEach(model.parameters) { NativeFormControl(field: $0).disabled(model.sending) }
                if let body = model.body {
                    ForEach(NativeFormGroups.names, id: \.self) { group in
                        let fields = NativeFormGroups.fields(body.children, in: group)
                        if !fields.isEmpty {
                            Section(group) {
                                ForEach(fields) { NativeFormControl(field: $0) }
                            }.disabled(loading || model.sending || model.committed || model.uncertain)
                        }
                    }
                }
                if loading {
                    ProgressView().controlSize(.small)
                }
                if let error = model.error {
                    Text(error).foregroundStyle(.red)
                }
                if let result = model.result {
                    Section("Result") { NativeRecordContent(value: result) }
                }
                if model.committed {
                    Label("Saved", systemImage: "checkmark.circle").foregroundStyle(.green)
                }
                if let validation = model.validationMessage, model.result == nil {
                    Text(validation).font(.caption).foregroundStyle(.secondary)
                }
            } else if let setupError {
                Text(setupError).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }

    private func submitButton(_ model: NativeFeatureFormModel) -> some View {
        Button(submitTitle(model)) {
            if model.operation.method == "DELETE" {
                confirmDeletion = true
            } else {
                submit(model)
            }
        }
        .disabled(loading || model.sending || model.committed || model.uncertain || model.validationMessage != nil)
    }

    private var dismissTitle: String {
        if model?.uncertain == true {
            return "Close"
        }
        return model?.operation.isWrite == true && model?.committed != true ? "Cancel" : "Done"
    }

    private func submitTitle(_ model: NativeFeatureFormModel) -> String {
        if !model.operation.isWrite {
            return "Show"
        }
        if model.operation.method == "DELETE" {
            return "Delete"
        }
        if model.operation.id.contains("invite") {
            return "Create Invitation"
        }
        if model.operation.method == "POST" {
            return "Create"
        }
        return "Save"
    }

    private func submit(_ model: NativeFeatureFormModel) {
        Task {
            if await model.submit(client: HackerRankClient(account: account),
                                  scimToken: account.isMock ? "demo-scim" : account.scimToken),
                model.operation.isWrite {
                onSaved()
            }
        }
    }

    private func loadExisting() async {
        guard let model else { return }

        let reads = ["api_update_test": "api_retrieve_test", "api_update_candidate": "api_show_candidate",
                     "api_update_interview": "api_show_interview", "api_update_question": "api_show_question",
                     "api_update_user": "api_retrieve_user", "api_update_team": "api_retrieve_team",
                     "api_scim_edit_user_put": "api_scim_retrieve_user"]
        guard let read = reads[model.operation.id] else { return }

        loading = true
        defer { loading = false }
        do {
            let response = try await HackerRankClient(account: account).executeAPI(
                read, pathParameters: model.path, scimToken: account.isMock ? "demo-scim" : account.scimToken
            )
            try Task.checkCancellation()
            if let data = response.data {
                let resource = data.object["model"] ?? data.object["data"] ?? data
                self.model = try NativeFeatureFormModel(operationID: model.operation.id, path: model.path,
                                                        initial: resource)
            }
        } catch {
            if !Task.isCancelled {
                model.error = rankCoverageError(error)
            }
        }
    }
}
