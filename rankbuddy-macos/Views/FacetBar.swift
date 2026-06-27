//
//  FacetBar.swift
//  rankbuddy-macos
//

import Flow
import SwiftUI

/// The faceted filter bar shown above a `LoadableList` (#55): a wrapping row of per-field
/// multi-select dropdowns, each populated from the loaded items, plus a Clear-all button when
/// any filter is active. Mirrors PadBuddy's list filter bar (State / Language / Owner …).
/// Renders nothing when no facets are declared, so unfaceted lists are unchanged.
struct FacetBar<Item>: View {
    let facets: [ListFacet<Item>]
    let items: [Item]
    @Binding var selected: [String: Set<String>]

    private var hasActiveSelection: Bool {
        selected.values.contains { !$0.isEmpty }
    }

    var body: some View {
        if !facets.isEmpty {
            HFlow(spacing: 8) {
                ForEach(facets) { facet in
                    facetMenu(facet)
                }

                if hasActiveSelection {
                    Button {
                        selected = [:]
                    } label: {
                        Label("Clear", systemImage: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear all filters")
                }
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func facetMenu(_ facet: ListFacet<Item>) -> some View {
        let options = ListQuery.facetOptions(facet, in: items)
        let chosen = selected[facet.id] ?? []
        return Menu {
            ForEach(options, id: \.self) { option in
                Toggle(isOn: binding(facet.id, option)) { Text(option) }
            }

            if !chosen.isEmpty {
                Divider()
                Button("Clear \(facet.label)") { selected[facet.id] = [] }
            }
        } label: {
            Label(chosen.isEmpty ? facet.label : "\(facet.label) (\(chosen.count))", systemImage: facet.systemImage)
        }
        .fixedSize()
        .disabled(options.isEmpty)
        .help("Filter by \(facet.label.lowercased())")
    }

    private func binding(_ facetID: String, _ option: String) -> Binding<Bool> {
        Binding(
            get: { selected[facetID]?.contains(option) ?? false },
            set: { isOn in
                var set = selected[facetID] ?? []
                if isOn { set.insert(option) } else { set.remove(option) }
                selected[facetID] = set
            }
        )
    }
}

#Preview {
    @Previewable @State var selected: [String: Set<String>] = ["state": ["Active"]]
    let facets = [
        ListFacet<String>("state", "State", systemImage: "circle.fill") { [$0] }
    ]
    return FacetBar(facets: facets, items: ["Active", "Closed", "Draft"], selected: $selected)
        .frame(width: 420)
}
