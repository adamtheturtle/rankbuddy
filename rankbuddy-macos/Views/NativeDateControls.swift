//
//  NativeDateControls.swift
//  rankbuddy-macos
//

import SwiftUI

struct NativeDateControl: View {
    @Bindable var field: NativeFormField
    @State private var date = Date()

    var body: some View {
        VStack(alignment: .leading) {
            NativeFormValue(title: field.required ? field.title : nil) {
                DatePicker(field.title, selection: Binding(get: { date }, set: {
                    date = $0
                    field.text = $0.ISO8601Format()
                }), displayedComponents: [.date, .hourAndMinute]).labelsHidden()
            }
            DisclosureGroup("Exact timestamp") {
                TextField("ISO 8601", text: $field.text).textFieldStyle(.roundedBorder)
                    .font(.body.monospaced()).padding(.top, 4)
            }.font(.caption).foregroundStyle(.secondary)
        }
        .onAppear {
            if let parsed = DisplayFormat.parseDate(field.text) {
                date = parsed
            } else if field.text.isEmpty {
                field.text = date.ISO8601Format()
            }
        }
    }
}

struct NativeDateRangeControl: View {
    @Bindable var field: NativeFormField
    @State private var start = Date().addingTimeInterval(-86400)
    @State private var end = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if field.required {
                Text(field.title).font(.headline)
            }
            VStack(spacing: 8) {
                DatePicker("From", selection: Binding(get: { start }, set: { start = $0; update() }),
                           displayedComponents: [.date, .hourAndMinute])
                DatePicker("To", selection: Binding(get: { end }, set: { end = $0; update() }),
                           displayedComponents: [.date, .hourAndMinute])
                DisclosureGroup("Exact range") {
                    TextField("From..to (ISO 8601)", text: $field.text).textFieldStyle(.roundedBorder)
                        .font(.body.monospaced()).padding(.top, 4)
                }.font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            let values = field.text.components(separatedBy: "..")
            if values.count == 2,
               let first = DisplayFormat.parseDate(values[0]), let last = DisplayFormat.parseDate(values[1]) {
                start = first
                end = last
            } else if field.text.isEmpty {
                update()
            }
        }
    }

    private func update() {
        field.text = "\(start.ISO8601Format())..\(end.ISO8601Format())"
    }
}
