//
//  SearchInterpreterTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

@MainActor
struct SearchInterpreterTests {
    private let languageFacet = SearchInterpreter.FacetDescriptor(
        id: "language", label: "Language", options: ["python", "cpp", "java"]
    )
    private let statusFacet = SearchInterpreter.FacetDescriptor(
        id: "status", label: "Status", options: ["Active", "Ended", "Draft"]
    )

    @Test func `prompt retrieval promotes matching options beyond the fixed prefix`() {
        let options = (1 ... 50).map { "Team \($0)" }
        let retrieved = SearchInterpreter.retrievedOptions(options, query: "Team 50 interviews", limit: 40)

        #expect(retrieved.count == 40)
        #expect(retrieved.first == "Team 50")
        #expect(retrieved.contains("Team 50"))
    }

    @Test func `parseModelResponse reads labeled fields and a multi-line filter block`() {
        let reply = """
        keywords: binary search
        dateRange: last 7 days
        filters:
        language=python
        status=Active
        """
        let fields = SearchInterpreter.parseModelResponse(reply)
        #expect(fields.keywords == "binary search")
        #expect(fields.dateRange == "last 7 days")
        #expect(fields.filters == "language=python\nstatus=Active")
    }

    @Test func `parseModelResponse tolerates blank fields and spacing variants`() {
        let fields = SearchInterpreter.parseModelResponse("Keywords:\nDate Range: last month\nfilters:")
        #expect(fields.keywords.isEmpty)
        #expect(fields.dateRange == "last month")
        #expect(fields.filters.isEmpty)
    }

    @Test func `parseFilters splits lines and semicolons into id=value pairs`() {
        let pairs = SearchInterpreter.parseFilters("language=python\nstatus=Active; language=java")
        let asDict = pairs.map { "\($0.facetID)=\($0.value)" }
        #expect(asDict == ["language=python", "status=Active", "language=java"])
    }

    @Test func `parseFilters splits comma-delimited pairs without breaking commas inside values`() {
        let pairs = SearchInterpreter.parseFilters("status=Active, role=Developer, location=London, UK")
        let asDict = pairs.map { "\($0.facetID)=\($0.value)" }
        #expect(asDict == ["status=Active", "role=Developer", "location=London, UK"])
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

    @Test func `groundFacetValue supports exact one-character option mentions`() {
        #expect(SearchInterpreter.groundFacetValue("C", facetOptions: ["C", "R"], query: "C questions") == "C")
        #expect(SearchInterpreter.groundFacetValue("R", facetOptions: ["C", "R"], query: "C questions") == nil)
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
        let reply = SearchInterpreter.ParsedReply(
            keywords: "python linked list questions",
            dateRange: "last 7 days",
            filters: "language=python\nstatus=Ended"
        )
        let result = SearchInterpreter.ground(
            reply,
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
        let reply = SearchInterpreter.ParsedReply(
            keywords: "all questions",
            dateRange: "last 7 days",
            filters: "status=Active"
        )
        let result = SearchInterpreter.ground(
            reply,
            query: "all questions",
            facets: [statusFacet],
            dateRangeSupported: true,
            dateRangeOptions: ["last 7 days"]
        )
        // "all" and "questions" are stop-words; status/date unsupported by the query.
        #expect(result.isEmpty)
    }
}
