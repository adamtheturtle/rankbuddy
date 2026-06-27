//
//  ListSearchPagingTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

/// Coverage for the client-side filter auto-load policy (#86): while a filter (search, facet, or
/// date) is active the list pages in more rows so the match isn't stuck on the first page, but
/// stays bounded so a vague filter can't drain a huge collection.
struct ListSearchPagingTests {
    @Test func `keeps loading while filtering with more pages and few matches`() {
        #expect(ListSearchPaging.shouldKeepLoading(
            isFiltering: true, visibleMatches: 2, hasMorePages: true, pagesLoadedThisFilter: 0
        ))
    }

    @Test func `never loads when nothing is filtering`() {
        #expect(!ListSearchPaging.shouldKeepLoading(
            isFiltering: false, visibleMatches: 0, hasMorePages: true, pagesLoadedThisFilter: 0
        ))
    }

    @Test func `stops once enough matches fill the view`() {
        #expect(!ListSearchPaging.shouldKeepLoading(
            isFiltering: true, visibleMatches: ListSearchPaging.matchTarget,
            hasMorePages: true, pagesLoadedThisFilter: 0
        ))
    }

    @Test func `stops when the list is exhausted`() {
        #expect(!ListSearchPaging.shouldKeepLoading(
            isFiltering: true, visibleMatches: 0, hasMorePages: false, pagesLoadedThisFilter: 0
        ))
    }

    @Test func `stops at the per-filter page cap so a vague filter stays bounded`() {
        #expect(!ListSearchPaging.shouldKeepLoading(
            isFiltering: true, visibleMatches: 0, hasMorePages: true,
            pagesLoadedThisFilter: ListSearchPaging.pageCap
        ))
    }
}
