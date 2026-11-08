//
//  NativeFeatureForm.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit
import Observation

struct NativeFeatureRequest {
    let path: [String: String]
    let query: [URLQueryItem]
    let body: HackerRankJSONValue?
}

enum NativeWriteFailure {
    static let message = "The change could not be confirmed. "
        + "Close this sheet and refresh before trying again."

    static func mightHaveCommitted(_ error: Error) -> Bool {
        if error is URLError || error is CancellationError {
            return true
        }
        if case HackerRankError.network = error {
            return true
        }
        if case let HackerRankError.http(status, _) = error {
            return status >= 500
        }
        return false
    }
}

@Observable
final class NativeFeatureFormModel {
    let operation: HackerRankAPIOperation
    let catalogue: HackerRankAPICatalogue
    let path: [String: String]
    var body: NativeFormField?
    var parameters: [NativeFormField]
    var result: HackerRankJSONValue?
    var error: String?
    var sending = false
    var committed = false
    var uncertain = false
    var original: [String: HackerRankJSONValue] = [:]

    init(operationID: String, path: [String: String] = [:], initial: HackerRankJSONValue? = nil) throws {
        let path = path.filter { !$0.value.isEmpty }
        let catalogue = try HackerRankClient.apiCatalogue()
        guard let operation = catalogue.operations.first(where: { $0.id == operationID }) else {
            throw NativeFormError.invalid("This feature is unavailable in the current API contract.")
        }

        self.catalogue = catalogue
        self.operation = operation
        self.path = path
        original = initial?.object ?? [:]
        if let schema = operation.bodySchema {
            body = NativeFormField(
                catalogue: catalogue,
                name: "Settings",
                schema: NativeFormSchema.bodySchema(schema, operation: operation, catalogue: catalogue),
                required: operation.bodyRequired,
                value: initial
            )
        }
        parameters = operation.parameters.filter { path[$0.name] == nil }.map { parameter in
            var schema: [String: HackerRankJSONValue] = ["type": .string(parameter.type),
                                                         "description": .string(parameter.description)]
            if let items = parameter.items {
                schema["items"] = items
            }
            if let enumeration = parameter.enumeration {
                schema["enum"] = enumeration
            }
            return NativeFormField(
                catalogue: catalogue,
                name: parameter.name,
                schema: .object(schema),
                required: parameter.required || parameter.location == "path"
            )
        }
        // PUT v3 resources accept partial updates. Unchecked fields keep their remote value.
        if operation.method == "PUT", !operation.scim, let body {
            body.children = body.children.map {
                NativeFormField(catalogue: catalogue, name: $0.name, schema: $0.schema, value: initial?.object[$0.name])
            }
        }
    }

    var validationMessage: String? {
        do { _ = try request(); return nil } catch { return error.localizedDescription }
    }

    func request() throws -> NativeFeatureRequest {
        var path = path
        var query: [URLQueryItem] = []
        for parameter in operation.parameters {
            guard let field = parameters.first(where: { $0.name == parameter.name }),
                  let value = try field.value() else { continue }

            let text: String = if case let .array(items) = value {
                items.map(\.text).joined(separator: ",")
            } else {
                value.text
            }
            if parameter.location == "path" {
                path[parameter.name] = text
            } else {
                query.append(URLQueryItem(name: parameter.name, value: text))
            }
        }
        var payload = try body?.value()
        if operation.method == "PUT", !operation.scim, case let .object(values) = payload {
            payload = .object(values.filter { original[$0.key] != $0.value })
        }
        if operation.scim, operation.method == "PATCH", var fields = payload?.object {
            fields["Operations"] = fields.removeValue(forKey: "operations")
            if fields["schemas"] == nil {
                fields["schemas"] = .array([.string("urn:ietf:params:scim:api:messages:2.0:PatchOp")])
            }
            payload = .object(fields)
        }
        try validate(query: query, body: payload)
        return NativeFeatureRequest(path: path, query: query, body: payload)
    }

    private func validate(query: [URLQueryItem], body: HackerRankJSONValue?) throws {
        let values = query.reduce(into: [String: String]()) { $0[$1.name] = $1.value }
        if let limit = values["limit"].flatMap(Int.init), limit < 1 {
            throw NativeFormError.invalid("Page size must be positive.")
        }
        if let offset = values["offset"].flatMap(Int.init), offset < 0 {
            throw NativeFormError.invalid("Offset cannot be negative.")
        }
        if values["source_id"] != nil, values["source_type"] == nil {
            throw NativeFormError.invalid("Choose a source type when filtering by source ID.")
        }
        if values["order_by"] != nil, values["order_dir"] == nil {
            throw NativeFormError.invalid("Choose a direction when ordering interviews.")
        }
        if let prompt = body?.object["custom_system_prompt"]?.text,
           let issue = QuestionEditValidation.systemPromptIssue(prompt) {
            throw NativeFormError.invalid(issue)
        }
        if let webhook = body?.object["webhook_authentication"]?.object {
            let data = webhook["data"]?.object ?? [:]
            let required = webhook["type"]?.text == "basic_auth" ? ["username", "password"] : ["token"]
            if required.contains(where: { data[$0]?.text.isEmpty != false }) {
                throw NativeFormError.invalid("Complete the selected webhook authentication fields.")
            }
        }
    }

    func submit(client: HackerRankClient, scimToken: String?) async -> Bool {
        guard !sending, !committed, !uncertain else { return false }

        sending = true
        defer { sending = false }
        error = nil
        do {
            let request = try request()
            let response = try await client.executeAPI(operation.id, pathParameters: request.path,
                                                       query: request.query, body: request.body, scimToken: scimToken)
            if operation.isWrite, response.data?.object["status"] == .bool(false) {
                throw NativeFormError
                    .invalid(response.data?.object["message"]?.text ?? "HackerRank rejected the change.")
            }
            result = response.data?.object["model"] ?? response.data
            committed = operation.isWrite
            return true
        } catch {
            if operation.isWrite {
                uncertain = NativeWriteFailure.mightHaveCommitted(error)
            }
            self.error = uncertain ? "The outcome could not be confirmed. Refresh the resource before trying again."
                : rankCoverageError(error)
            return false
        }
    }
}
