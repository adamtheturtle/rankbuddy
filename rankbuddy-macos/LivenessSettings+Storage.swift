//
//  LivenessSettings+Storage.swift
//  rankbuddy-macos
//

import Foundation

extension LivenessSettings {
    static func clearSeen(accountID: UUID, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: seenKey(accountID))
    }
}
