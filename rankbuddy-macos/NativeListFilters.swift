//
//  NativeListFilters.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

/// Fields owned by controls outside the sheet must survive Apply and Reset unchanged.
enum NativeListFilters {
    static func draft(
        operationID: String, query: [URLQueryItem], excluding: Set<String>
    ) throws -> NativeFeatureFormModel {
        let draft = try NativeFeatureFormModel(operationID: operationID)
        draft.parameters.removeAll { field in
            excluding.contains(field.name)
                || draft.operation.parameters.contains { $0.name == field.name && $0.location == "path" }
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
        return draft
    }

    static func applying(
        _ filters: [URLQueryItem], to query: [URLQueryItem], preserving: Set<String>
    ) -> [URLQueryItem] {
        filters.filter { !preserving.contains($0.name) } + query.filter { preserving.contains($0.name) }
    }
}
