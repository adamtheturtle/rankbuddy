//
//  WindowToolbar.swift
//  rankbuddy-macos
//

import SwiftUI

extension EnvironmentValues {
    @Entry var mainWindowOwnsNavigation = false
}

/// Section changes update items without replacing the main window's customization owner.
private struct WindowToolbarModifier<Items: CustomizableToolbarContent>: ViewModifier {
    @Environment(\.mainWindowOwnsNavigation) private var mainWindowOwnsNavigation
    let id: String
    @ToolbarContentBuilder let items: () -> Items

    func body(content: Content) -> some View {
        if mainWindowOwnsNavigation {
            content.toolbar { items() }
        } else {
            content.toolbar(id: id) { items() }
        }
    }
}

extension View {
    func windowToolbar(
        id: String, @ToolbarContentBuilder content: @escaping () -> some CustomizableToolbarContent
    ) -> some View {
        modifier(WindowToolbarModifier(id: id, items: content))
    }
}
