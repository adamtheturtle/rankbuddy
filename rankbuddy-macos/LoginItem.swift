//
//  LoginItem.swift
//  rankbuddy-macos
//

import ServiceManagement

/// A thin wrapper over `SMAppService.mainApp` for the "Launch at login" setting (#62).
///
/// The system, not `UserDefaults`, is the source of truth: `isEnabled` reads the live
/// registration status, and the Settings toggle mirrors it. Registering/unregistering can
/// throw, so the caller surfaces the error and reflects the real state rather than assuming
/// the change took.
enum LoginItem {
    /// Whether the app is currently registered to launch at login.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item. Throws if the system rejects the
    /// change (e.g. the user disabled it in System Settings → General → Login Items).
    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
