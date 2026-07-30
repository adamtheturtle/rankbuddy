//
//  QuestionCodeStubSheets.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

/// A sheet that asks HackerRank to generate per-language code stubs for a coding question
/// from a function signature (#147).
struct GenerateCodeStubsSheet: View {
    let questionID: String
    let account: Account

    @Environment(\.dismiss) private var dismiss
    @State private var functionName = ""
    @State private var returnType = ""
    @State private var parameters = ""
    @State private var languages = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Function name", text: $functionName)
                    TextField("Return type", text: $returnType, prompt: Text("e.g. int"))
                    TextField(
                        "Parameters",
                        text: $parameters,
                        prompt: Text("name: type pairs, comma-separated, e.g. counts: int[], target: int")
                    )
                    TextField("Languages", text: $languages, prompt: Text("Comma-separated; empty for all"))
                } footer: {
                    Text("HackerRank writes a starter stub for each language from this signature.")
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Generate Code Stubs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Generate") { Task { await generate() } }
                            .disabled(functionName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .frame(width: 480, height: errorMessage == nil ? 320 : 400)
    }

    private func generate() async {
        let parsed = parsedParameters
        if let duplicate = CodeStubValidation.duplicateParameterName(in: parsed) {
            errorMessage = "Parameter name “\(duplicate)” is repeated."
            return
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            _ = try await HackerRankClient(account: account).generateCodeStubs(
                questionID: questionID,
                body: GenerateCodeStubsBody(
                    functionName: nonBlank(functionName),
                    returnType: nonBlank(returnType),
                    parameters: parsed,
                    languages: splitList(languages)
                )
            )
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// "counts: int[], target: int" → [(counts, int[]), (target, int)]; malformed pairs are
    /// dropped rather than failing the whole request.
    private var parsedParameters: [GenerateCodeStubsBody.Parameter]? {
        let pairs = parameters.split(separator: ",").compactMap { pair -> GenerateCodeStubsBody.Parameter? in
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }

            let name = parts[0].trimmingCharacters(in: .whitespaces)
            let type = parts[1].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !type.isEmpty else { return nil }

            return GenerateCodeStubsBody.Parameter(name: name, type: type)
        }
        return pairs.isEmpty ? nil : pairs
    }
}

/// A sheet that sets one language's custom code stub on a coding question (#147).
struct CustomCodeStubSheet: View {
    let questionID: String
    let account: Account

    @Environment(\.dismiss) private var dismiss
    @State private var language = ""
    @State private var code = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        CodeStubValidation.normalizedLanguage(language) != nil && CodeStubValidation.hasSource(code)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Language", text: $language, prompt: Text("e.g. python"))
                }

                Section("Stub code") {
                    TextField("Stub code", text: $code, axis: .vertical)
                        .lineLimit(6 ... 14)
                        .labelsHidden()
                        .font(.body.monospaced())
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Set Custom Code Stub")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSending)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Save") { Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
        }
        .frame(width: 480, height: errorMessage == nil ? 420 : 500)
    }

    private func save() async {
        guard let normalizedLanguage = CodeStubValidation.normalizedLanguage(language) else {
            errorMessage = "Language must not be blank."
            return
        }
        guard CodeStubValidation.hasSource(code) else {
            errorMessage = "Stub code must not be blank."
            return
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            _ = try await HackerRankClient(account: account).updateCustomCodeStubs(
                questionID: questionID,
                body: CustomCodeStubsBody(stubs: [
                    .init(language: normalizedLanguage, code: code)
                ])
            )
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Request bodies

nonisolated enum CodeStubValidation {
    static func duplicateParameterName(in parameters: [GenerateCodeStubsBody.Parameter]?) -> String? {
        var seen: Set<String> = []
        return parameters?.lazy.map(\.name).first { name in
            !seen.insert(name.folding(options: .caseInsensitive, locale: .current)).inserted
        }
    }

    static func normalizedLanguage(_ language: String) -> String? {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func hasSource(_ code: String) -> Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// These mirror HackerRankKit's typed requests (which land in a future Kit release); Kit
// 0.4.0's codestub endpoints accept any `Encodable` body. Synthesized encoding omits
// `nil` fields, so only the fields the user filled in are sent.

/// The body for `PUT /questions/{id}/generate`.
nonisolated struct GenerateCodeStubsBody: Encodable {
    nonisolated struct Parameter: Encodable {
        let name: String
        let type: String
    }

    var functionName: String?
    var returnType: String?
    var parameters: [Parameter]?
    var languages: [String]?

    enum CodingKeys: String, CodingKey {
        case functionName = "function_name"
        case returnType = "return_type"
        case parameters
        case languages
    }
}

/// The body for `PUT /questions/{id}/custom_codestubs`.
nonisolated struct CustomCodeStubsBody: Encodable {
    nonisolated struct Stub: Encodable {
        let language: String
        let code: String
    }

    var stubs: [Stub]

    enum CodingKeys: String, CodingKey {
        case stubs = "custom_codestubs"
    }
}
