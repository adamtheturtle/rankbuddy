//
//  APIExplorerView.swift
//  rankbuddy-macos
//

import BuddyAppKit
import Foundation
import HackerRankKit
import SwiftUI

/// An account-scoped surface for every documented read, write, ATS and provisioning operation.
struct APIExplorerView: View {
    @Environment(AccountStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var catalogue: HackerRankAPICatalogue?
    @State private var selectedOperationID: String?
    @State private var selectedAccountID: UUID?
    @State private var search = ""
    @State private var pathText = "{}"
    @State private var queryText = "{}"
    @State private var bodyText = "{}"
    @State private var scimTokenDraft = ""
    @State private var output = "Run an operation to see its response."
    @State private var errorMessage: String?
    @State private var running = false

    private var account: Account? {
        store.accounts.first { $0.id == selectedAccountID }
    }

    private var operation: HackerRankAPIOperation? {
        catalogue?.operations.first { $0.id == selectedOperationID }
    }

    private var visibleOperations: [HackerRankAPIOperation] {
        (catalogue?.operations ?? []).filter { item in
            search.isEmpty || "\(item.summary) \(item.group) \(item.method) \(item.path)"
                .localizedCaseInsensitiveContains(search)
        }.sorted { ($0.group, $0.summary) < ($1.group, $1.summary) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedOperationID) {
                ForEach(visibleOperations) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.summary)
                        Text("\(item.method) · \(item.group)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(item.id)
                }
            }
            .disabled(running)
            .searchable(text: $search, prompt: "Find an API operation")
            .navigationTitle("API Explorer")
            .navigationSplitViewColumnWidth(min: 230, ideal: 280)
        } detail: {
            if let operation {
                operationView(operation)
            } else {
                ContentUnavailableView("Choose an Operation", systemImage: "network",
                                       description: Text("Browse all documented HackerRank API operations."))
            }
        }
        .frame(minWidth: 1000, minHeight: 680)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .task {
            do {
                catalogue = try HackerRankClient.apiCatalogue()
                selectedOperationID = catalogue?.operations.first?.id
                selectedAccountID = store.currentAccountID ?? store.accounts.first?.id
                resetInputs()
            } catch { errorMessage = rankCoverageError(error) }
        }
        .onChange(of: selectedOperationID) { resetInputs() }
        .onChange(of: selectedAccountID) { resetInputs() }
    }

    private func operationView(_ operation: HackerRankAPIOperation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            accountPicker
            Text(operation.summary).font(.title2.bold())
            Text("\(operation.method) \(operation.path)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if operation.scim {
                provisioningCredential
            }
            requestAndResponse(operation)
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            HStack {
                Link("API Documentation", destination: URL(string: "https://www.hackerrank.com/work/apidocs")
                    ?? URL(fileURLWithPath: "/"))
                Spacer()
                if running {
                    ProgressView().controlSize(.small)
                }
                Button(operation.summary) { Task { await execute(operation) } }
                    .buttonStyle(.borderedProminent)
                    .disabled(running || account == nil)
            }
        }
        .padding()
    }

    private func requestAndResponse(_ operation: HackerRankAPIOperation) -> some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    inputEditor("Path parameters", text: $pathText, height: 80)
                    inputEditor("Query parameters", text: $queryText, height: 100)
                    if operation.bodySchema != nil {
                        inputEditor("Request body", text: $bodyText, height: 180)
                    }
                    if let catalogue {
                        DisclosureGroup("Request format") {
                            Text(APIExplorerFormatting.json(catalogue.inputSchema(for: operation)))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
                .padding(.trailing, 8)
            }
            .frame(minWidth: 300)
            ScrollView {
                Text(output)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(.leading, 8)
            }
            .frame(minWidth: 300)
        }
    }

    private var accountPicker: some View {
        Picker("Account", selection: $selectedAccountID) {
            ForEach(store.accounts) { item in Text(item.label).tag(Optional(item.id)) }
        }
        .disabled(running)
    }

    private var provisioningCredential: some View {
        HStack {
            SecureField("SCIM provisioning token", text: $scimTokenDraft)
            Button("Save Token") {
                guard var current = account else { return }

                current.scimToken = scimTokenDraft.isEmpty ? nil : scimTokenDraft
                store.update(current)
            }
            .disabled(running || account == nil)
        }
        .help("Stored in the account Keychain item. SCIM uses a separate provisioning credential.")
    }

    private func inputEditor(_ title: String, text: Binding<String>, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(title) (JSON)").font(.headline)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: height)
                .border(.separator)
                .disabled(running)
        }
    }

    private func resetInputs() {
        guard !running else { return }

        let parameters = operation?.parameters.filter { $0.location == "path" }
        let path = parameters?.reduce(into: [String: HackerRankJSONValue]()) {
            $0[$1.name] = .string("")
        } ?? [:]
        pathText = APIExplorerFormatting.json(.object(path))
        queryText = "{}"
        bodyText = "{}"
        scimTokenDraft = account?.scimToken ?? ""
        output = "Run an operation to see its response."
        errorMessage = nil
    }

    private func execute(_ operation: HackerRankAPIOperation) async {
        guard let account, !running else { return }

        running = true
        errorMessage = nil
        defer { running = false }
        do {
            let input = try APIExplorerFormatting.inputs(path: pathText, query: queryText,
                                                         body: operation.bodySchema == nil ? nil : bodyText)
            let response = try await HackerRankClient(account: account).executeAPI(
                operation.id, pathParameters: input.pathParameters, query: input.query, body: input.body,
                scimToken: account.isMock ? "demo-scim" : scimTokenDraft
            )
            output = try APIExplorerFormatting.response(response)
        } catch let HackerRankError.http(0, message) {
            errorMessage = message
        } catch is DecodingError {
            errorMessage = "Path, query and request body fields must contain valid JSON."
        } catch { errorMessage = rankCoverageError(error) }
    }
}

nonisolated enum APIExplorerFormatting {
    static func json(_ value: HackerRankJSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return "{}" }

        return String(data: data, encoding: .utf8) ?? "{}"
    }

    static func inputs(path: String, query: String, body: String?) throws -> HackerRankAPIInputs {
        let decoder = JSONDecoder()
        var fields: [String: HackerRankJSONValue] = try [
            "path": decoder.decode(HackerRankJSONValue.self, from: Data(path.utf8)),
            "query": decoder.decode(HackerRankJSONValue.self, from: Data(query.utf8))
        ]
        if let body {
            fields["body"] = try decoder.decode(HackerRankJSONValue.self, from: Data(body.utf8))
        }
        return try HackerRankAPIInputs(value: .object(fields))
    }

    static func response(_ response: HackerRankAPIResponse) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(response)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
