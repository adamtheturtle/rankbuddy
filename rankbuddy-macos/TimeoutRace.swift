//
//  TimeoutRace.swift
//  rankbuddy-macos
//

import Foundation

/// Resolves an asynchronous operation at most once without structured concurrency waiting for
/// losing work to finish after the deadline.
nonisolated enum TimeoutRace {
    private final class Continuation<Value: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Value?, Never>?

        init(_ continuation: CheckedContinuation<Value?, Never>) {
            self.continuation = continuation
        }

        func resume(returning value: Value?) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: value)
        }
    }

    static func first<Value: Sendable>(
        timeout: Duration,
        operation: @escaping @Sendable () async -> Value?
    ) async -> Value? {
        await withCheckedContinuation { continuation in
            let resolver = Continuation(continuation)
            Task {
                let value = await operation()
                resolver.resume(returning: value)
            }
            Task {
                try? await Task.sleep(for: timeout)
                resolver.resume(returning: nil)
            }
        }
    }
}
