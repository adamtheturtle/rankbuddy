//
//  LoadableList+Toolbar.swift
//  rankbuddy-macos
//

import BuddyAppKit
import BuddyDesignSystem
import SwiftUI

extension LoadableList {
    /// The list's customizable toolbar (#101). Built as identified `ToolbarItem`s so the window's
    /// "Customize Toolbar…" sheet can add, remove, and reorder them. The day-to-day actions — the
    /// section's write action and Refresh — show by default; the rarer ones (Smart Filter, Saved
    /// Searches, CSV export) are `defaultCustomization(.hidden)`, so the default toolbar stays
    /// uncluttered while every action remains one customization away. Items only appear when the
    /// list actually offers the capability (a date chip, sorting, export, …).
    @ToolbarContentBuilder
    var customToolbar: some CustomizableToolbarContent {
        // The section's write action (e.g. "Invite Candidate", "Create User"); empty for the
        // read-only lists. Kept fixed at the leading edge — it's the primary action.
        ToolbarItem(id: "accessory", placement: .primaryAction) {
            accessoryToolbar()
        }
        .customizationBehavior(.disabled)

        if filterDate != nil {
            ToolbarItem(id: "dateFilter", placement: .automatic) {
                FilterChipMenu(
                    title: dateFilterLabel,
                    icon: "calendar",
                    selected: $dateRange,
                    options: NamedDateRange.options,
                    formatter: { $0.capitalized }
                )
                .help("Filter \(title) by date")
            }
        }

        if !sortOptions.isEmpty {
            ToolbarItem(id: "sort", placement: .automatic) {
                Menu {
                    Picker("Sort By", selection: $sortSelection) {
                        ForEach(sortOptions) { option in
                            Text(option.label).tag(Optional(option.id))
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort \(title)")
            }
        }

        // Plain-language filtering, interpreted on-device (#91). Hidden by default and entirely
        // absent when the model is unavailable, so the affordance never dead-ends.
        if SearchInterpreter.isAvailable {
            ToolbarItem(id: "smartFilter", placement: .automatic) {
                Button {
                    smartFilterFailed = false
                    showSmartFilter = true
                } label: {
                    Label("Smart Filter", systemImage: "sparkle.magnifyingglass")
                }
                .help("Filter \(title) with a plain-language request, interpreted on your device")
                .keyboardShortcut("f", modifiers: [.command, .shift])
            }
            .defaultCustomization(.hidden)
        }

        if let restorationKey {
            ToolbarItem(id: "savedSearch", placement: .automatic) {
                SavedSearchMenu(
                    title: title,
                    restorationKey: restorationKey,
                    query: $query,
                    dateRange: $dateRange
                )
            }
            .defaultCustomization(.hidden)
        }

        if let csvExport {
            ToolbarItem(id: "exportCSV", placement: .automatic) {
                Button {
                    CSVExport.save(csvExport(visibleItems), suggestedName: csvFilename)
                } label: {
                    Label("Export CSV…", systemImage: "tablecells")
                }
                .help("Export \(title) as CSV")
            }
            .defaultCustomization(.hidden)

            ToolbarItem(id: "exportSelected", placement: .automatic) {
                Button {
                    CSVExport.save(csvExport(selectedItems), suggestedName: "\(csvFilename)-selected")
                } label: {
                    Label("Export Selected (\(selection.count))…", systemImage: "tablecells.badge.ellipsis")
                }
                .help("Export the selected \(title) as CSV (#44)")
            }
            // Only meaningful with a selection; stays in Customize but hides from the bar until then.
            .hidden(selection.isEmpty)
            .defaultCustomization(.hidden)
        }

        ToolbarItem(id: "refresh", placement: .automatic) {
            Button {
                Task { await reload() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(isLoading)
        }
    }
}
