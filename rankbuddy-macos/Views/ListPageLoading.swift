//
//  ListPageLoading.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

/// Cancellation ends a UI load without publishing a page or a retryable failure.
enum ListPageLoading {
    static func load<Item: Sendable>(
        _ operation: () async throws -> Page<Item>
    ) async throws -> Page<Item>? {
        do {
            try Task.checkCancellation()
            let page = try await operation()
            try Task.checkCancellation()
            return page
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                return nil
            }
            throw error
        }
    }
}
