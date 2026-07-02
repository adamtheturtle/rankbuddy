//
//  AppDelegate.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit

/// Minimal app delegate, used for the Dock right-click menu (#45). PadBuddy offers quick
/// section jumps from its Dock icon; this mirrors that — each item selects a sidebar section
/// (the same persisted `selectedSection` the menu bar and deep links use) and brings the app
/// forward.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The "Open in RankBuddy" Service provider (#46), held so it isn't deallocated.
    private let servicesProvider = ServicesProvider()

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.servicesProvider = servicesProvider
        NSUpdateDynamicServices()
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for section in SidebarSection.allCases {
            let item = NSMenuItem(
                title: section.title,
                action: #selector(openSection(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = section.rawValue
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openSection(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }

        UserDefaults.standard.set(raw, forKey: SidebarSection.defaultsKey)
        AppActivator.bringToFront()
        NSApp.windows.first(where: \.canBecomeMain)?.makeKeyAndOrderFront(nil)
    }
}
