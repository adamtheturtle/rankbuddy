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
    @State private var mutationTask: Task<Void, Never>?

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
                    Button("Cancel") {
                        mutationTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Generate") { mutationTask = Task { await generate() } }
                            .disabled(nonBlank(functionName) == nil)
                    }
                }
            }
        }
        .frame(width: 480, height: errorMessage == nil ? 320 : 400)
        .interactiveDismissDisabled(isSending)
        .onDisappear { mutationTask?.cancel() }
    }

    private func generate() async {
        guard let normalizedFunctionName = nonBlank(functionName) else {
            errorMessage = "Function name must not be blank."
            return
        }
        guard CodeStubValidation.isPortableIdentifier(normalizedFunctionName) else {
            errorMessage = "Function name must start with a letter or underscore "
                + "and contain only letters, numbers, and underscores."
            return
        }

        if let malformed = CodeStubValidation.malformedParameter(in: parameters) {
            errorMessage = "Parameter “\(malformed)” must use name: type format."
            return
        }

        let parsed = parsedParameters
        if let invalid = CodeStubValidation.invalidParameterIdentifier(in: parsed) {
            errorMessage = "Parameter name “\(invalid)” is not a valid identifier."
            return
        }
        if let duplicate = CodeStubValidation.duplicateParameterName(in: parsed) {
            errorMessage = "Parameter name “\(duplicate)” is repeated."
            return
        }
        let parsedLanguages = splitList(languages)
        if let issue = CodeStubValidation.generationBoundsIssue(
            functionName: normalizedFunctionName,
            returnType: nonBlank(returnType),
            parameters: parsed,
            languages: parsedLanguages
        ) {
            errorMessage = issue
            return
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            _ = try await HackerRankClient(account: account).generateCodeStubs(
                questionID: questionID,
                options: CodeStubGenerationOptions(
                    functionName: normalizedFunctionName,
                    returnType: nonBlank(returnType),
                    parameters: parsed,
                    languages: parsedLanguages
                )
            )
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// "counts: int[], target: int" → [(counts, int[]), (target, int)]; malformed pairs are
    /// dropped rather than failing the whole request.
    private var parsedParameters: [CodeStubParameter]? {
        CodeStubValidation.parsedParameters(in: parameters)
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
    @State private var mutationTask: Task<Void, Never>?

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
                    Button("Cancel") {
                        mutationTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Save") { mutationTask = Task { await save() } }
                            .disabled(!canSave)
                    }
                }
            }
        }
        .frame(width: 480, height: errorMessage == nil ? 420 : 500)
        .interactiveDismissDisabled(isSending)
        .onDisappear { mutationTask?.cancel() }
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

        if let issue = CodeStubValidation.customStubBoundsIssue(language: normalizedLanguage, code: code) {
            errorMessage = issue
            return
        }

        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            _ = try await HackerRankClient(account: account).updateCustomCodeStubs(
                questionID: questionID,
                stubs: [QuestionCodeStub(language: normalizedLanguage, code: code)]
            )
            dismiss()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Request bodies

nonisolated enum CodeStubValidation {
    static let maxFieldLength = 255
    static let maxParameters = 100
    static let maxLanguages = 100
    static let maxSourceLength = 1_000_000

    static func parsedParameters(in text: String) -> [CodeStubParameter]? {
        let pairs = text.split(separator: ",").compactMap { pair -> CodeStubParameter? in
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return nil }

            let name = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let type = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !type.isEmpty else { return nil }

            return CodeStubParameter(name: name, type: type)
        }
        return pairs.isEmpty ? nil : pairs
    }

    static func malformedParameter(in text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        for rawPair in text.split(separator: ",", omittingEmptySubsequences: false) {
            let pair = rawPair.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = pair.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  !parts[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !parts[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return pair.isEmpty ? "(blank)" : pair
            }
        }
        return nil
    }

    static func duplicateParameterName(in parameters: [CodeStubParameter]?) -> String? {
        var seen: Set<String> = []
        return parameters?.lazy.map(\.name).first { name in
            !seen.insert(name.folding(options: .caseInsensitive, locale: .current)).inserted
        }
    }

    static func invalidParameterIdentifier(in parameters: [CodeStubParameter]?) -> String? {
        parameters?.lazy.map(\.name).first { !isPortableIdentifier($0) }
    }

    static func isPortableIdentifier(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        guard let first = scalars.first, isASCIILetter(first) || first.value == 95 else { return false }

        return scalars.dropFirst().allSatisfy {
            isASCIILetter($0) || (48 ... 57).contains($0.value) || $0.value == 95
        }
    }

    private static func isASCIILetter(_ scalar: Unicode.Scalar) -> Bool {
        (65 ... 90).contains(scalar.value) || (97 ... 122).contains(scalar.value)
    }

    static func generationBoundsIssue(
        functionName: String,
        returnType: String?,
        parameters: [CodeStubParameter]?,
        languages: [String]?
    ) -> String? {
        if functionName.count > maxFieldLength {
            return "Function name is too long (maximum 255 characters)."
        }
        if let returnType, returnType.count > maxFieldLength {
            return "Return type is too long (maximum 255 characters)."
        }
        if let parameters, parameters.count > maxParameters {
            return "Use at most 100 parameters."
        }
        if let parameter = parameters?.first(where: {
            $0.name.count > maxFieldLength || $0.type.count > maxFieldLength
        }) {
            return "Parameter “\(parameter.name)” has a name or type longer than 255 characters."
        }
        if let languages, languages.count > maxLanguages {
            return "Use at most 100 languages."
        }
        if languages?.contains(where: { $0.count > maxFieldLength }) == true {
            return "Language names must be at most 255 characters."
        }
        return nil
    }

    static func customStubBoundsIssue(language: String, code: String) -> String? {
        if language.count > maxFieldLength {
            return "Language must be at most 255 characters."
        }
        if code.count > maxSourceLength {
            return "Stub code must be at most 1,000,000 characters."
        }
        return nil
    }

    static func normalizedLanguage(_ language: String) -> String? {
        let normalized = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    static func hasSource(_ code: String) -> Bool {
        !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
