//
//  NativeFormControls.swift
//  rankbuddy-macos
//

import HackerRankKit
import SwiftUI

struct NativeFormControl: View {
    @Bindable var field: NativeFormField
    @Environment(\.nativeFeatureAccount) private var account
    @Environment(\.nativeFormOmissionLabel) private var omissionLabel
    var namedEntry = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if namedEntry {
                TextField("Field name", text: $field.name)
            }
            if !field.required, field.kind == "boolean" {
                Picker(field.title, selection: Binding(
                    get: { field.included ? (field.boolean ? "yes" : "no") : "default" },
                    set: { field.included = $0 != "default"; field.boolean = $0 == "yes" }
                )) {
                    Text(omissionLabel).tag("default")
                    Text("Yes").tag("yes")
                    Text("No").tag("no")
                }
            } else {
                if !field.required {
                    Toggle(field.title, isOn: $field.included)
                        .help("Include a value for this setting")
                }
                if field.included || field.required {
                    VStack(alignment: .leading, spacing: 8) {
                        valueControl
                        if let description = field.schema.object["description"]?.text {
                            NativeFormHelp(html: description)
                        }
                    }
                    .padding(.leading, field.required ? 0 : 12)
                }
            }
        }
        .accessibilityIdentifier("field-\(field.name)")
    }

    @ViewBuilder private var valueControl: some View {
        if let collection = NativeEntityCollection(field: field.name), let account {
            NativeEntityPicker(field: field, collection: collection, account: account)
        } else if ["created_at", "updated_at", "ended_at"].contains(field.name),
                  field.schema.object["description"]?.text.contains("from..to") == true {
            NativeDateRangeControl(field: field)
        } else if field.schema.object["type"]?.text == "datetime" {
            NativeDateControl(field: field)
        } else if !field.choices.isEmpty {
            NativeFormValue(title: field.required ? field.title : nil) {
                Picker(field.title, selection: $field.text) {
                    ForEach(field.choices, id: \.self) { Text(NativeFormSchema.optionTitle($0.text)).tag($0.text) }
                }.labelsHidden()
            }
        } else {
            if field.schema.object.isEmpty || !(field.schema.object["type"]?.array.isEmpty ?? true) {
                Picker("Value type", selection: $field.kind) {
                    ForEach(field.kinds, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }
            switch field.kind {
            case "boolean": Toggle(field.title, isOn: $field.boolean)
            case "array", "object": collection
            case "null": Text("Empty value").foregroundStyle(.secondary)
            default: scalar
            }
        }
    }

    @ViewBuilder private var scalar: some View {
        if ["password", "secret", "token", "authorization"].contains(where: {
            field.name.localizedCaseInsensitiveContains($0)
        }) {
            NativeFormValue(title: field.required ? field.title : nil) {
                SecureField(field.title, text: $field.text).labelsHidden().textFieldStyle(.roundedBorder)
            }
        } else if ["content", "instructions", "problem_statement", "internal_notes", "custom_system_prompt",
                   "message", "input", "output"].contains(field.name) {
            if field.required {
                Text(field.title).font(.headline)
            }
            TextEditor(text: $field.text)
                .scrollContentBackground(.hidden)
                .padding(6).frame(minHeight: 112)
                .background(.background, in: RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).stroke(.separator) }
                .accessibilityLabel(field.title)
        } else {
            NativeFormValue(title: field.required ? field.title : nil) {
                TextField(field.title, text: $field.text).labelsHidden().textFieldStyle(.roundedBorder)
            }
        }
    }

    private var collection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(field.children) { child in AnyView(Self(field: child)) }
                ForEach(field.entries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        AnyView(Self(field: entry, namedEntry: field.kind == "object"))
                        Button("Remove", systemImage: "minus.circle") {
                            field.entries.removeAll { $0.id == entry.id }
                        }.labelStyle(.iconOnly).help("Remove this item")
                    }
                }
                if field.kind == "array" || field.allowsExtraProperties {
                    Button(field.kind == "array" ? "Add Item" : "Add Field", systemImage: "plus") { field.addEntry() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
        } label: {
            if field.required {
                Text(field.title)
            }
        }
    }
}

/// Displays structured business data without exposing a JSON request/response console.
struct NativeRecordContent: View {
    let value: HackerRankJSONValue
    var label = "Details"
    var style = NativeRecordStyle.general
    var fieldNameValue = false

    var body: some View {
        if ["password", "token", "secret", "authorization"].contains(where: {
            label.localizedCaseInsensitiveContains($0)
        }) {
            LabeledContent(label, value: "••••••••")
        } else {
            switch value {
            case let .object(fields):
                if label == "Details" {
                    objectContent(fields)
                } else {
                    GroupBox(label) {
                        objectContent(fields).padding(8)
                    }
                }

            case let .array(items):
                GroupBox(label) {
                    VStack(alignment: .leading, spacing: 12) {
                        if items.isEmpty {
                            Text("None").foregroundStyle(.secondary)
                        }
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            AnyView(Self(value: item, label: "Item \(index + 1)", style: style,
                                         fieldNameValue: style == .audit && label == "Changed Fields"))
                            Divider()
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }

            case .null: LabeledContent(label, value: "Not set")

            case let .bool(flag): LabeledContent(label, value: flag ? "Yes" : "No")

            default:
                if let url = URL.remoteWebURL(from: value.text) {
                    LabeledContent(label) { Link(value.text, destination: url) }
                } else {
                    LabeledContent(label) {
                        Text(displayValue)
                            .textSelection(.enabled)
                            .help(value.text)
                    }
                }
            }
        }
    }

    private var displayValue: String {
        if fieldNameValue {
            return NativeRecordPresentation.label(value.text, style: style)
        }
        return label.hasSuffix(" At") ? DisplayFormat.date(value.text) ?? value.text : value.text
    }

    private func objectContent(_ fields: [String: HackerRankJSONValue]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(fields.keys.sorted(), id: \.self) { key in
                if let value = fields[key] {
                    AnyView(Self(value: value, label: NativeRecordPresentation.label(key, style: style), style: style))
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
