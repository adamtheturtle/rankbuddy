//
//  FacetBar.swift
//  rankbuddy-macos
//

import BuddyDesignSystem
import Flow
import SwiftUI

/// The faceted filter bar shown above a `LoadableList` (#55): a wrapping row of per-field
/// multi-select chips, each populated from the loaded items, plus a Clear-all button when any
/// filter is active. Each facet renders as PadBuddy's capsule `ChipMenuShell` — neutral when
/// idle, accent with an inline × when active (#109) — the same chip vocabulary as the date chip.
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
            // Leading-align the chips against the window edge, matching PadBuddy's filter bar;
            // without this the HFlow centres them in the column width, which reads as unpolished.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func facetMenu(_ facet: ListFacet<Item>) -> some View {
        let options = ListQuery.facetOptions(facet, in: items)
        let chosen = selected[facet.id] ?? []
        let isActive = !chosen.isEmpty
        return ChipMenuShell(
            icon: facet.systemImage,
            text: isActive ? "\(facet.label) (\(chosen.count))" : facet.label,
            isActive: isActive,
            fillColor: isActive ? Color.accentColor.opacity(0.18) : .chipIdleFill,
            strokeColor: isActive ? Color.accentColor.opacity(0.4) : .subtleStroke,
            labelColor: chipLabelColor(isActive: isActive),
            menuDisabled: options.isEmpty,
            clearLabel: "Clear \(facet.label) filter",
            onClear: { selected[facet.id] = [] },
            menu: {
                // Multi-select: each value is a toggle, so several can be active at once.
                ForEach(options, id: \.self) { option in
                    Toggle(isOn: binding(facet.id, option)) { Text(option) }
                }
            }
        )
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
