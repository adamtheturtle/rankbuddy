//
//  ListPageLoadingTests.swift
//  rankbuddy-macosTests
//

import Foundation
import HackerRankKit
@testable import rankbuddy_macos
import Testing

@MainActor
struct ListPageLoadingTests {
    @Test func `task cancellation is not a retryable load failure`() async throws {
        let page: Page<String>? = try await ListPageLoading.load {
            throw CancellationError()
        }

        #expect(page == nil)
        #expect(!Task.isCancelled)
    }

    @Test func `URLSession cancellation is not a retryable load failure`() async throws {
        let page: Page<String>? = try await ListPageLoading.load {
            throw URLError(.cancelled)
        }

        #expect(page == nil)
    }

    @Test func `a cancelled task cannot publish a late successful page`() async throws {
        let task = Task {
            try await ListPageLoading.load {
                withUnsafeCurrentTask { $0?.cancel() }
                return Page(items: ["late"], next: "next-page")
            }
        }

        #expect(try await task.value == nil)
    }

    @Test func `an already cancelled load does not start a request`() async throws {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ListPageLoading.load {
                Issue.record("A cancelled load started a request")
                return Page(items: ["unexpected"], next: nil)
            }
        }

        #expect(try await task.value == nil)
    }

    @Test func `real network failures still reach the retry path`() async {
        do {
            let _: Page<String>? = try await ListPageLoading.load {
                throw URLError(.timedOut)
            }
            Issue.record("Expected the network failure to propagate")
        } catch let error as URLError {
            #expect(error.code == .timedOut)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func `successful loads preserve rows and pagination`() async throws {
        let page = try await ListPageLoading.load {
            Page(items: ["first", "second"], next: "next-page", totalCount: 3)
        }

        #expect(page?.items == ["first", "second"])
        #expect(page?.next == "next-page")
        #expect(page?.totalCount == 3)
    }
}
