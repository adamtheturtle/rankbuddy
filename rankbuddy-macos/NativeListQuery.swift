//
//  NativeListQuery.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit
import SwiftUI

enum NativeListQuery {
    static func page<Item: Decodable & Sendable & Identifiable>(
        _: Item.Type, client: HackerRankClient, operationID: String,
        path: [String: String] = [:], query: [URLQueryItem] = [], cursor: String? = nil
    ) async throws -> Page<Item> {
        let catalogue = try HackerRankClient.apiCatalogue()
        guard let operation = catalogue.operations.first(where: { $0.id == operationID }) else {
            throw NativeFormError.invalid("The requested collection is unavailable.")
        }

        var route = operation.path
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        for (key, value) in path {
            guard let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) else {
                throw NativeFormError.invalid("Invalid resource identifier.")
            }

            route = route.replacingOccurrences(of: "{\(key)}", with: encoded)
        }
        var query = query
        if !query.contains(where: { $0.name == "limit" }) {
            query.append(URLQueryItem(name: "limit", value: "100"))
        }
        let raw = try await client.resourceJSON(path: route, after: cursor, query: query)
        let envelope = try HackerRankClient.makeDecoder().decode(
            HackerRankPage<Item>.self, from: HackerRankClient.makeEncoder().encode(raw)
        )
        return Page(items: envelope.data, next: envelope.next, totalCount: envelope.totalCount)
    }
}

private struct NativeListFiltersModifier: ViewModifier {
    let operationID: String
    @Binding var query: [URLQueryItem]
    @State private var presented = false

    private var filterSymbol: String {
        query.isEmpty ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill"
    }

    func body(content: Content) -> some View {
        content
            .id(query.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"))
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(
                        "Filters",
                        systemImage: filterSymbol
                    ) {
                        presented = true
                    }
                    .help("Filter this collection on HackerRank")
                }
            }
            .sheet(isPresented: $presented) {
                NativeListFiltersSheet(operationID: operationID, query: $query)
            }
    }
}

struct NativeListFiltersSheet: View {
    let operationID: String
    @Binding var query: [URLQueryItem]
    @Environment(\.dismiss) private var dismiss
    @State private var model: NativeFeatureFormModel?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                if let model {
                    ForEach(model.parameters.filter { parameter in
                        model.operation.parameters.contains { $0.name == parameter.name && $0.location == "query" }
                    }) { NativeFormControl(field: $0) }
                }
                if let error {
                    Text(error).foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .automatic) { Button("Reset") { query = []; dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        do { query = try model?.request().query ?? []; dismiss() } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
            }
        }
        .frame(width: 600, height: 560)
        .task {
            do {
                let draft = try NativeFeatureFormModel(operationID: operationID)
                draft.parameters.removeAll { field in
                    draft.operation.parameters.contains { $0.name == field.name && $0.location == "path" }
                        || (operationID == "api_list_all_interview_templates" && field.name == "filter")
                }
                for item in query {
                    if let field = draft.parameters.first(where: { $0.name == item.name }) {
                        field.included = true
                        field.text = item.value ?? ""
                        field.boolean = item.value == "true"
                        if field.kind == "array" {
                            for text in (item.value ?? "").split(separator: ",") {
                                field.addEntry()
                                field.entries.last?.text = String(text)
                            }
                        }
                    }
                }
                model = draft
            } catch { self.error = error.localizedDescription }
        }
    }
}

extension View {
    func nativeListFilters(_ operationID: String, query: Binding<[URLQueryItem]>) -> some View {
        modifier(NativeListFiltersModifier(operationID: operationID, query: query))
    }
}
