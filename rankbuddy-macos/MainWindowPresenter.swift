//
//  MainWindowPresenter.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit
import SwiftUI

/// Retains SwiftUI's scene-opening action so callbacks outside the view tree can recreate the
/// unique main window after the user closes it.
@MainActor
final class MainWindowPresenter {
    static let shared = MainWindowPresenter()
    private var openMainWindow: (@MainActor () -> Void)?

    private init() {}

    func register(openMainWindow: @escaping @MainActor () -> Void) {
        self.openMainWindow = openMainWindow
    }

    func show() {
        if let openMainWindow {
            openMainWindow()
        } else {
            NSApp.windows.first(where: { $0.title == "RankBuddy" })?.makeKeyAndOrderFront(nil)
        }
        AppActivator.bringToFront()
    }
}

struct MainWindowRegistration: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                MainWindowPresenter.shared.register {
                    openWindow(id: WindowID.main)
                }
            }
    }
}
