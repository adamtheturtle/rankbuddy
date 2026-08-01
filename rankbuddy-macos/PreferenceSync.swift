//
//  PreferenceSync.swift
//  rankbuddy-macos
//

import Foundation
import OSLog

nonisolated enum SyncedPreferenceValue: Codable, Equatable {
    case bool(Bool)
    case integer(Int)
    case double(Double)
    case string(String)
}

nonisolated struct PreferenceSyncPayload: Codable {
    let values: [String: SyncedPreferenceValue]
    let modifiedAt: Date
}

/// Synchronizes an explicit privacy/device-suitability allowlist of app-global preferences.
/// Account credentials, biometric policy, browser choice, MCP write permission, window state,
/// and other machine-specific/security-sensitive settings are deliberately excluded.
@MainActor
final class PreferenceSyncCoordinator {
    static let key = "rankbuddy.preferences"
    static let modifiedAtKey = "rankbuddy.preferences.modifiedAt"
    static let allowedKeys: Set<String> = [
        AppAppearance.defaultsKey,
        GeneralSettings.refreshSecondsKey,
        MenuBarPreferences.recentCountKey,
        MenuBarPreferences.activeOnlyKey,
        LivenessSettings.backgroundUpdatesKey,
        LivenessSettings.notifyKey,
        LivenessSettings.intervalMinutesKey,
        LivenessSettings.dockScopeKey,
        ListLayout.detailPaneHiddenKey
    ]

    private static let maximumFutureSkew: TimeInterval = 5 * 60
    private static let logger = Logger(subsystem: "com.adamdangoor.rankbuddy", category: "preference-sync")
    private let store: KeyValueSyncStore
    private let defaults: UserDefaults
    private var observer: Task<Void, Never>?
    private var isAdopting = false
    private var isActive = false
    private var lastSnapshot: [String: SyncedPreferenceValue]

    init(store: KeyValueSyncStore, defaults: UserDefaults = .standard) {
        self.store = store
        self.defaults = defaults
        lastSnapshot = Self.snapshot(defaults: defaults)
    }

    deinit { observer?.cancel() }

    func start() {
        store.onAvailabilityChange = { [weak self] in self?.availabilityChanged() }
        store.onExternalChange = { [weak self] in self?.adoptRemote() }
        observer = Task { @MainActor [weak self] in
            for await _ in NotificationCenter.default.notifications(named: UserDefaults.didChangeNotification) {
                self?.localDefaultsChanged()
            }
        }
        availabilityChanged()
    }

    static func snapshot(defaults: UserDefaults) -> [String: SyncedPreferenceValue] {
        var result: [String: SyncedPreferenceValue] = [:]
        for key in allowedKeys {
            switch defaults.object(forKey: key) {
            case let value as Bool: result[key] = .bool(value)
            case let value as Int: result[key] = .integer(value)
            case let value as Double: result[key] = .double(value)
            case let value as String: result[key] = .string(value)
            default: break
            }
        }
        return result
    }

    static func apply(_ values: [String: SyncedPreferenceValue], defaults: UserDefaults) {
        for key in allowedKeys {
            guard let value = values[key] else {
                defaults.removeObject(forKey: key)
                continue
            }

            switch value {
            case let .bool(value): defaults.set(value, forKey: key)
            case let .integer(value): defaults.set(value, forKey: key)
            case let .double(value): defaults.set(value, forKey: key)
            case let .string(value): defaults.set(value, forKey: key)
            }
        }
    }

    private func availabilityChanged() {
        guard store.isAvailable else { isActive = false; return }
        guard !isActive else { return }

        isActive = true
        adoptRemote()
        store.synchronize()
    }

    private func localDefaultsChanged() {
        guard !isAdopting else { return }

        let snapshot = Self.snapshot(defaults: defaults)
        guard snapshot != lastSnapshot else { return }

        lastSnapshot = snapshot
        defaults.set(Date(), forKey: Self.modifiedAtKey)
        pushLocal()
    }

    func adoptRemote() {
        guard store.isAvailable else { return }
        guard let data = store.data(forKey: Self.key) else { pushLocal(); return }
        guard let payload = try? JSONDecoder().decode(PreferenceSyncPayload.self, from: data) else {
            Self.logger.error("Replacing malformed remote preferences with local state")
            pushLocal()
            return
        }
        guard payload.modifiedAt.timeIntervalSinceNow <= Self.maximumFutureSkew else {
            Self.logger.error("Rejecting preferences with an implausible future timestamp")
            pushLocal()
            return
        }

        let localDate = defaults.object(forKey: Self.modifiedAtKey) as? Date ?? .distantPast
        guard localDate <= payload.modifiedAt else { pushLocal(); return }

        isAdopting = true
        Self.apply(payload.values, defaults: defaults)
        defaults.set(payload.modifiedAt, forKey: Self.modifiedAtKey)
        lastSnapshot = Self.snapshot(defaults: defaults)
        isAdopting = false
    }

    func pushLocal() {
        guard !isAdopting, store.isAvailable else { return }

        let modifiedAt = defaults.object(forKey: Self.modifiedAtKey) as? Date ?? .distantPast
        let payload = PreferenceSyncPayload(values: Self.snapshot(defaults: defaults), modifiedAt: modifiedAt)
        guard let data = try? JSONEncoder().encode(payload) else { return }

        store.setData(data, forKey: Self.key)
        store.synchronize()
    }
}
