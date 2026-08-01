//
//  AppPresenceMonitor.swift
//  rankbuddy-macos
//

import AppKit
import BuddyAppKit
import Foundation

/// Keeps AppKit's activation policy aligned with the persisted visibility preference even
/// when no SwiftUI window content is mounted.
@MainActor
final class AppPresenceMonitor {
    private let defaults: UserDefaults
    private let notificationCenter: NotificationCenter
    private let currentPolicy: () -> NSApplication.ActivationPolicy
    private let setPolicy: (NSApplication.ActivationPolicy) -> Bool
    private let activate: () -> Void
    private var observer: NSObjectProtocol?

    init(
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        currentPolicy: @escaping () -> NSApplication.ActivationPolicy = {
            NSApplication.shared.activationPolicy()
        },
        setPolicy: @escaping (NSApplication.ActivationPolicy) -> Bool = {
            NSApplication.shared.setActivationPolicy($0)
        },
        activate: @escaping () -> Void = { AppActivator.bringToFront() }
    ) {
        self.defaults = defaults
        self.notificationCenter = notificationCenter
        self.currentPolicy = currentPolicy
        self.setPolicy = setPolicy
        self.activate = activate
    }

    isolated deinit {
        if let observer {
            notificationCenter.removeObserver(observer)
        }
    }

    func start() {
        guard observer == nil else { return }

        reconcile()
        observer = notificationCenter.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            _ = MainActor.assumeIsolated {
                self?.reconcile()
            }
        }
    }

    @discardableResult
    func reconcile() -> AppPresence {
        AppPresence.current(defaults: defaults).applyDockVisibilityReconciling(
            defaults: defaults,
            currentPolicy: currentPolicy,
            setPolicy: setPolicy,
            activate: activate
        )
    }
}
