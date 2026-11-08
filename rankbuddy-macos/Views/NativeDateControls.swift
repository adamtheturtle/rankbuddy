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
            DatePicker(field.title, selection: Binding(get: { date }, set: {
                date = $0
                field.text = $0.ISO8601Format()
            }), displayedComponents: [.date, .hourAndMinute])
            TextField("Exact timestamp (ISO 8601)", text: $field.text)
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
        GroupBox(field.title) {
            VStack {
                DatePicker("From", selection: Binding(get: { start }, set: { start = $0; update() }),
                           displayedComponents: [.date, .hourAndMinute])
                DatePicker("To", selection: Binding(get: { end }, set: { end = $0; update() }),
                           displayedComponents: [.date, .hourAndMinute])
                TextField("Exact range (from..to)", text: $field.text)
            }
            .padding(6)
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
