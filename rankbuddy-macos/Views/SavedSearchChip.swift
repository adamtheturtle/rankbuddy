//
//  SavedSearchChip.swift
//  rankbuddy-macos
//

import BuddyDesignSystem
import SwiftUI

/// A saved-search recall token shown in the filter bar (#25), mirroring PadBuddy's chip. Tapping
/// one *applies* a saved set of filters rather than toggling a value, so it stays neutral until
/// applied — at which point it wears the same accent the active filter chips use. Deliberately a
/// rounded *rectangle* rather than the filter chips' capsule, so recall tokens and filter pills
/// read as distinct families even when both glow accent while applied.
struct SavedSearchChip: View {
    let name: String
    var systemImage: String = "bookmark.fill"
    /// True while the list's live filters exactly match this search — derived by the parent from
    /// filter state rather than stored, so it can never drift out of sync with what's shown.
    var isActive: Bool = false
    let onApply: () -> Void
    /// Omitted for any built-in defaults, which can't be deleted.
    var onDelete: (() -> Void)?

    @State private var hovered = false

    /// The token shape: a rounded rectangle, deliberately distinct from the filter chips' capsule.
    static let tokenShape = RoundedRectangle(cornerRadius: 6, style: .continuous)

    private var fillStyle: AnyShapeStyle {
        if isActive { return AnyShapeStyle(Color.accentColor.opacity(0.16)) }
        return hovered ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary)
    }

    private var strokeColor: Color {
        isActive ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08)
    }

    /// White on the accent glass capsule (macOS 26), accent on the light fallback fill (macOS 15)
    /// while applied, primary when idle — so an applied chip's text stays readable.
    private var contentColor: AnyShapeStyle {
        isActive ? AnyShapeStyle(chipLabelColor(isActive: true)) : AnyShapeStyle(.primary)
    }

    private var iconColor: AnyShapeStyle {
        isActive ? AnyShapeStyle(chipLabelColor(isActive: true)) : AnyShapeStyle(.secondary)
    }

    /// Clamp to the same limit names are capped to on save, with a trailing ellipsis, so no single
    /// chip overflows the bar; the full name stays in the accessibility label below.
    private var displayName: String {
        guard name.count > SavedSearch.maxNameLength else { return name }

        return String(name.prefix(SavedSearch.maxNameLength - 1)) + "…"
    }

    var body: some View {
        // The chip is exposed as a button via `accessibilityAddTraits` below, which this rule's
        // matcher doesn't detect on a tap-gesture view.
        // swiftlint:disable:next accessibility_trait_for_button
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.caption2)
                .accessibilityHidden(true)
                .foregroundStyle(iconColor)
            Text(displayName)
                .font(.caption.weight(.medium))
                .foregroundStyle(contentColor)
                .lineLimit(1)
            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .foregroundStyle(iconColor)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete saved search \(name)")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .chipCapsule(
            glassTint: isActive ? .accentColor : nil,
            fallbackFill: fillStyle,
            fallbackStroke: strokeColor,
            fallbackStrokeWidth: 0.5,
            in: Self.tokenShape
        )
        .contentShape(Self.tokenShape)
        .onTapGesture { onApply() }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel("Apply saved search \(name)")
    }
}

#Preview {
    HStack {
        SavedSearchChip(name: "Recent failures", isActive: false, onApply: {}, onDelete: {})
        SavedSearchChip(name: "Last 7 days", isActive: true, onApply: {}, onDelete: {})
    }
    .padding()
}
