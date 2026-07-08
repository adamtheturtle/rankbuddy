//
//  UndoAction.swift
//  rankbuddy-macos
//

import Foundation

/// A tiny object target for `UndoManager` when the reversible operation lives in SwiftUI view
/// state rather than an observable reference type.
@MainActor
final class UndoAction: NSObject {
    private let action: @MainActor () -> Void

    init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    func perform() {
        action()
    }
}
