//
//  LoadableList+Toolbar.swift
//  rankbuddy-macos
//

import BuddyAppKit
import BuddyDesignSystem
import HackerRankKit
import SwiftUI

/// Layout preferences shared across every list (#53).
enum ListLayout {
    /// Shared `@AppStorage` key toggling the persistent detail pane, mirroring PadBuddy's
    /// detail-pane toggle. Every list reads it, so hiding the pane in one section hides it in all,
    /// and the View ▸ Hide Detail Pane command (⌃⌘D) and the toolbar button stay in lockstep.
    static let detailPaneHiddenKey = "detailPaneHidden"
}

extension LoadableList {
    var csvExportIsPartial: Bool {
        nextCursor != nil
    }

    var csvExportSuggestedName: String {
        csvExportIsPartial ? "\(csvFilename)-loaded" : csvFilename
    }

    /// The list's customizable toolbar (#101). Built as identified `ToolbarItem`s so the window's
    /// "Customize Toolbar…" sheet can add, remove, and reorder them. The day-to-day actions — the
    /// section's write action and Refresh — show by default; the rarer ones (CSV export) are
    /// `defaultCustomization(.hidden)`, so the default toolbar stays uncluttered while every action
    /// remains one customization away. Items only appear when the list actually offers the
    /// capability (sorting, export, …). Filtering itself — the facet/date chips and Saved
    /// Searches — lives in the filter bar above the rows (see `LoadableList+FilterBar`), not the
    /// toolbar, mirroring PadBuddy.
    @ToolbarContentBuilder
    var customToolbar: some CustomizableToolbarContent {
        // The section's write action (e.g. "Invite Candidate", "Create User"); empty for the
        // read-only lists. Kept fixed at the leading edge — it's the primary action.
        ToolbarItem(id: "accessory", placement: .primaryAction) {
            accessoryToolbar()
        }
        .customizationBehavior(.disabled)

        if !sortOptions.isEmpty {
            ToolbarItem(id: "sort", placement: .automatic) {
                Menu {
                    // Two inline radio sections — sort field, then direction — mirroring
                    // PadBuddy's Sort menu. Without `.inline`, the pickers would render as
                    // nested "Sort By ▸" / "Order ▸" submenus inside the Sort button.
                    Picker("Sort By", selection: $sortSelection) {
                        ForEach(sortOptions) { option in
                            Label(option.label, systemImage: option.systemImage)
                                .tag(Optional(option.id))
                        }
                    }
                    .pickerStyle(.inline)

                    if let option = sortOptions.first(where: { $0.id == sortSelection }) {
                        let labels = option.kind.directionLabels
                        Picker("Order", selection: $sortReversed) {
                            Label(labels.forward, systemImage: "arrow.down").tag(false)
                            Label(labels.reversed, systemImage: "arrow.up").tag(true)
                        }
                        .pickerStyle(.inline)
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort \(title)")
            }
        }

        if let csvExport {
            ToolbarItem(id: "exportCSV", placement: .automatic) {
                Button {
                    let snapshot = visibleItems
                    CSVExport.save({ csvExport(snapshot) }, suggestedName: csvExportSuggestedName)
                } label: {
                    Label(csvExportIsPartial ? "Export Loaded Rows CSV…" : "Export CSV…", systemImage: "tablecells")
                }
                .help(
                    csvExportIsPartial
                        ? "Export the currently loaded \(title) rows as CSV"
                        : "Export \(title) as CSV"
                )
            }
            .defaultCustomization(.hidden)

            ToolbarItem(id: "exportSelected", placement: .automatic) {
                Button {
                    let snapshot = selectedItems
                    CSVExport.save({ csvExport(snapshot) }, suggestedName: "\(csvFilename)-selected")
                } label: {
                    let title = selection.isEmpty ? "Export Selected…" : "Export Selected (\(selection.count))…"
                    Label(title, systemImage: "tablecells.badge.ellipsis")
                }
                .help("Export the selected \(title) as CSV (#44)")
            }
            // Only meaningful with a selection; stays in Customize but hides from the bar until then.
            .hidden(selection.isEmpty)
            .defaultCustomization(.hidden)
        }

        // Off the default toolbar (⌘R lives on the Go menu), but one Customize Toolbar away —
        // matching PadBuddy, which keeps Reload out of the default bar too.
        ToolbarItem(id: "refresh", placement: .automatic) {
            Button {
                Task { await reload() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
        }
        .defaultCustomization(.hidden)

        // Hides/shows the persistent detail pane (#53). The View ▸ Hide Detail Pane command (⌃⌘D)
        // is the primary control, so — like PadBuddy — this button is off the default toolbar but
        // available via Customize; it lives in the always-present list toolbar so "Show Detail
        // Pane" is still reachable once the pane is hidden. Animates the swap like the sidebar.
        ToolbarItem(id: "toggleDetailPane", placement: .automatic) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth) { detailPaneHidden.toggle() }
            } label: {
                Label(detailPaneHidden ? "Show Detail Pane" : "Hide Detail Pane",
                      systemImage: "sidebar.right")
            }
            .help(detailPaneHidden ? "Show the detail pane" : "Hide the detail pane")
        }
        .defaultCustomization(.hidden)
    }
}
