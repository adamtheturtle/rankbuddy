//
//  NativeFormFields.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit
import Observation

extension HackerRankJSONValue {
    nonisolated var object: [String: Self] {
        if case let .object(value) = self {
            return value
        }
        return [:]
    }

    nonisolated var array: [Self] {
        if case let .array(value) = self {
            return value
        }
        return []
    }

    nonisolated var text: String {
        switch self {
        case let .string(value): value
        case let .int(value): String(value)
        case let .double(value): String(value)
        case let .bool(value): value ? "true" : "false"
        case .null: ""
        case .array, .object: ""
        }
    }
}

enum NativeFormError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self {
        case let .invalid(message): message
        }
    }
}

/// Native controls share wire-schema validation, while each resource owns its actions and navigation.
enum NativeFormSchema {
    static func bodySchema(_ schema: HackerRankJSONValue, operation: HackerRankAPIOperation,
                           catalogue: HackerRankAPICatalogue) -> HackerRankJSONValue {
        var result = resolve(schema, catalogue: catalogue).object
        var properties = result["properties"]?.object ?? [:]
        if operation.scim, properties["emails"] != nil {
            // The service requires SCIM address objects, despite the legacy array<string> documentation.
            properties["emails"] = .object([
                "type": .string("array"), "items": .object([
                    "type": .string("object"), "required": .array([.string("value")]),
                    "properties": .object(["value": .object(["type": .string("string")]),
                                           "primary": .object(["type": .string("boolean")]),
                                           "type": .object(["type": .string("string")])])
                ])
            ])
            properties["name"] = .object([
                "type": .string("object"), "properties": .object([
                    "givenName": .object(["type": .string("string")]),
                    "familyName": .object(["type": .string("string")])
                ])
            ])
        }
        if properties["interviewers"] != nil {
            properties["interviewers"] = .object([
                "type": .string("array"), "items": .object([
                    "type": .array([.string("string"), .string("object")]),
                    "required": .array([.string("email")]),
                    "properties": .object(["email": .object(["type": .string("string")]),
                                           "name": .object(["type": .string("string")])])
                ])
            ])
        }
        if operation.id == "api_update_question" {
            properties["custom_system_prompt"] = .object([
                "type": .string("string"),
                "description": .string("Custom system prompt for project questions. Whitespace is preserved.")
            ])
        }
        if operation.scim {
            properties["schemas"] = .object(["type": .string("array"),
                                             "items": .object(["type": .string("string")])])
            if operation.method == "PATCH" {
                properties["operations"] = scimPatchOperations
            }
        }
        if var answer = properties["answer"]?.object {
            answer["items"] = .object(["type": .string("integer")])
            properties["answer"] = .object(answer)
        }
        result["properties"] = .object(properties)
        return .object(result)
    }

    private static var scimPatchOperations: HackerRankJSONValue {
        .object([
            "type": .string("array"), "items": .object([
                "type": .string("object"), "required": .array([.string("op")]),
                "properties": .object([
                    "op": .object(["type": .string("string"),
                                   "enum": .array([.string("add"), .string("replace"), .string("remove")])]),
                    "path": .object(["type": .string("string")]), "value": .object([:])
                ])
            ])
        ])
    }

    static func resolve(_ schema: HackerRankJSONValue, catalogue: HackerRankAPICatalogue) -> HackerRankJSONValue {
        var result = schema.object
        if let reference = result["$ref"]?.text.split(separator: "/").last,
           let definition = catalogue.definitions[String(reference)] {
            result.removeValue(forKey: "$ref")
            result = resolve(definition, catalogue: catalogue).object.merging(result) { _, supplied in supplied }
        }
        if let parts = result.removeValue(forKey: "allOf")?.array {
            var properties = result["properties"]?.object ?? [:]
            var required = result["required"]?.array ?? []
            for part in parts {
                let resolved = resolve(part, catalogue: catalogue).object
                properties.merge(resolved["properties"]?.object ?? [:]) { _, value in value }
                required += resolved["required"]?.array ?? []
            }
            result["properties"] = .object(properties)
            result["required"] = .array(required)
        }
        return .object(result)
    }

    static func title(_ name: String) -> String {
        let names = [
            "from": "Starts",
            "to": "Ends",
            "limit": "Page Size",
            "offset": "Skip Records",
            "diplayName": "Group Name",
            "userName": "Username",
            "firstname": "First Name",
            "lastname": "Last Name",
            "qid": "Question ID",
            "rollable_type": "Share With",
            "rollable_id": "Person or Team ID",
            "role_name": "Access",
            "op": "Change",
            "value": "Value",
            "ide_config": "Editor Configuration",
            "functionName": "Function Name",
            "functionParams": "Function Parameters",
            "functionReturn": "Return Type",
            "allowedLanguages": "Allowed Languages"
        ]
        return names[name] ?? name.replacingOccurrences(of: "_", with: " ").capitalized
            .replacingOccurrences(of: " Id", with: " ID").replacingOccurrences(of: " Url", with: " URL")
    }
}

@Observable
final class NativeFormField: Identifiable {
    let id = UUID()
    var name: String
    let schema: HackerRankJSONValue
    let required: Bool
    private let initialValue: HackerRankJSONValue?
    let catalogue: HackerRankAPICatalogue
    var included: Bool
    var kind: String
    var text = ""
    var boolean = false
    var children: [NativeFormField] = []
    var entries: [NativeFormField] = []

    init(catalogue: HackerRankAPICatalogue, name: String, schema: HackerRankJSONValue,
         required: Bool = false, value: HackerRankJSONValue? = nil) {
        self.name = name
        self.catalogue = catalogue
        self.schema = NativeFormSchema.resolve(schema, catalogue: catalogue)
        self.required = required
        initialValue = value
        included = required || value != nil
        let properties = self.schema.object["properties"]?.object ?? [:]
        kind = Self.initialKind(schema: self.schema, value: value)
        let requiredNames = Set(self.schema.object["required"]?.array.map(\.text) ?? [])
        children = properties.keys.sorted().map { key in
            let property = properties[key] ?? .object([:])
            return NativeFormField(
                catalogue: catalogue,
                name: key,
                schema: property,
                required: requiredNames.contains(key) || property.object["required"] == .bool(true),
                value: value?.object[key]
            )
        }
        if let value {
            hydrate(value)
        } else if let first = self.schema.object["enum"]?.array.first {
            text = first.text
        }
    }

    private static func initialKind(schema: HackerRankJSONValue, value: HackerRankJSONValue?) -> String {
        let type = schema.object["type"]
        if let value, type == nil || !(type?.array.isEmpty ?? true) {
            return kind(of: value)
        }
        let declared = type?.array.first?.text ?? type?.text
        if let declared, !declared.isEmpty {
            return declared == "datetime" ? "string" : declared
        }
        return schema.object["properties"]?.object.isEmpty == false ? "object" : "string"
    }

    private static func kind(of value: HackerRankJSONValue) -> String {
        switch value {
        case .string: "string"
        case .int: "integer"
        case .double: "number"
        case .bool: "boolean"
        case .null: "null"
        case .array: "array"
        case .object: "object"
        }
    }

    private func hydrate(_ value: HackerRankJSONValue) {
        text = value.text
        if case let .bool(flag) = value {
            boolean = flag
        }
        if case let .object(values) = value {
            let properties = schema.object["properties"]?.object ?? [:]
            entries = values.keys.sorted().filter { properties[$0] == nil }.map { key in
                NativeFormField(catalogue: catalogue, name: key, schema: .object([:]),
                                required: true, value: values[key])
            }
        }
        if case let .array(values) = value {
            entries = values.enumerated().map { index, item in
                NativeFormField(catalogue: catalogue, name: "Item \(index + 1)",
                                schema: schema.object["items"] ?? .object([:]), required: true, value: item)
            }
        }
    }

    var choices: [HackerRankJSONValue] {
        var values = schema.object["enum"]?.array ?? []
        if !values.isEmpty, let initialValue, !values.contains(initialValue) {
            values.append(initialValue)
        }
        return values
    }

    var kinds: [String] {
        if let types = schema.object["type"], !types.array.isEmpty {
            return types.array.map(\.text)
        }
        return ["string", "integer", "number", "boolean", "object", "array", "null"]
    }

    var title: String {
        NativeFormSchema.title(name)
    }

    var allowsExtraProperties: Bool {
        schema.object["additionalProperties"] != .bool(false)
    }

    func addEntry() {
        let item = kind == "array" ? schema.object["items"] ?? .object([:]) : .object([:])
        entries.append(NativeFormField(
            catalogue: catalogue,
            name: kind == "array" ? "Item \(entries.count + 1)" : "",
            schema: item,
            required: true
        ))
    }

    func value() throws -> HackerRankJSONValue? {
        guard included || required else { return nil }

        if !choices.isEmpty {
            guard let chosen = choices.first(where: { $0.text == text }) else {
                throw NativeFormError.invalid("Choose a value for \(title).")
            }

            return chosen
        }
        switch kind {
        case "object": return try objectValue()
        case "array": return try .array(entries.compactMap { try $0.value() })
        case "boolean": return .bool(boolean)
        default: return try scalarValue()
        }
    }

    private func objectValue() throws -> HackerRankJSONValue {
        var values: [String: HackerRankJSONValue] = [:]
        for child in children + entries {
            if let value = try child.value() {
                guard !child.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw NativeFormError.invalid("Enter a name for each \(title.lowercased()) field.")
                }
                guard values[child.name] == nil else {
                    throw NativeFormError.invalid("\(child.title) is included more than once.")
                }

                values[child.name] = value
            }
        }
        return .object(values)
    }

    private func scalarValue() throws -> HackerRankJSONValue {
        switch kind {
        case "integer":
            guard let number = Int(text) else { throw NativeFormError.invalid("\(title) needs a whole number.") }

            return .int(number)

        case "number":
            guard let number = Double(text), number.isFinite else {
                throw NativeFormError.invalid("\(title) needs a number.")
            }

            return .double(number)

        case "null": return .null

        default:
            if required, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               ![
                   "content",
                   "internal_notes",
                   "instructions",
                   "message",
                   "explanation",
                   "input",
                   "output",
                   "problem_statement"
               ]
               .contains(name) {
                throw NativeFormError.invalid("\(title) is required.")
            }
            return .string(text)
        }
    }
}
