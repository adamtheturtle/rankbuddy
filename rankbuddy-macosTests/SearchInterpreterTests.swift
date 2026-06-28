//
//  SearchInterpreterTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

struct SearchInterpreterTests {
    private let languageFacet = SearchInterpreter.FacetDescriptor(
        id: "language", label: "Language", options: ["python", "cpp", "java"]
    )
    private let statusFacet = SearchInterpreter.FacetDescriptor(
        id: "status", label: "Status", options: ["Active", "Ended", "Draft"]
    )

    @Test func `parseFilters splits lines and semicolons into id=value pairs`() {
        let pairs = SearchInterpreter.parseFilters("language=python\nstatus=Active; language=java")
        let asDict = pairs.map { "\($0.facetID)=\($0.value)" }
        #expect(asDict == ["language=python", "status=Active", "language=java"])
    }

    @Test func `parseFilters ignores malformed entries`() {
        #expect(SearchInterpreter.parseFilters("nonsense\n=value\nid=").isEmpty)
    }

    @Test func `groundFacetValue keeps a real option only when the query names it`() {
        // The query mentions "python", so the matching option is kept (canonical casing).
        #expect(
            SearchInterpreter.groundFacetValue("Python", facetOptions: languageFacet.options, query: "python questions")
                == "python"
        )
        // The model grabbed "cpp" but the query never said it — rejected.
        #expect(
            SearchInterpreter.groundFacetValue("cpp", facetOptions: languageFacet.options, query: "python questions")
                == nil
        )
        // Not a real option — rejected even if the query says it.
        #expect(
            SearchInterpreter.groundFacetValue("rust", facetOptions: languageFacet.options, query: "rust questions")
                == nil
        )
    }

    @Test func `groundDateRange keeps a range only when the query mentions time`() {
        #expect(SearchInterpreter.groundDateRange("last 7 days", query: "questions from last week") == "last 7 days")
        #expect(SearchInterpreter.groundDateRange("last 7 days", query: "python questions") == nil)
    }

    @Test func `groundText drops stop-words and matched facet value words`() {
        // "questions" is a stop-word; "python" is a facet value word; "binary search" survives.
        let kept = SearchInterpreter.groundText(
            "python binary search questions",
            facetValueWords: ["python"]
        )
        #expect(kept == "binary search")
    }

    @Test func `ground rejects over-filled values and keeps grounded ones`() {
        // The model named python (in query), a date (query says "last week"), and over-filled
        // status=Ended which the query never mentions.
        let raw = ModelInterpretation(
            keywords: "python linked list questions",
            dateRange: "last 7 days",
            filters: "language=python\nstatus=Ended"
        )
        let result = SearchInterpreter.ground(
            raw,
            query: "python linked list questions from last week",
            facets: [languageFacet, statusFacet],
            dateRangeSupported: true,
            dateRangeOptions: ["last 7 days", "last 30 days"]
        )

        #expect(result.facets["language"] == ["python"])
        #expect(result.facets["status"] == nil) // over-filled, query never says "ended"
        #expect(result.dateRange == "last 7 days")
        #expect(result.query == "linked list") // stop-words + "python" stripped
        #expect(!result.isEmpty)
    }

    @Test func `ground returns empty when nothing is supported`() {
        let raw = ModelInterpretation(keywords: "all questions", dateRange: "last 7 days", filters: "status=Active")
        let result = SearchInterpreter.ground(
            raw,
            query: "all questions",
            facets: [statusFacet],
            dateRangeSupported: true,
            dateRangeOptions: ["last 7 days"]
        )
        // "all" and "questions" are stop-words; status/date unsupported by the query.
        #expect(result.isEmpty)
    }
}
