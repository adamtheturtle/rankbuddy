//
//  ClientFilterTokenTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

struct ClientFilterTokenTests {
    @Test func `facet delimiters cannot collide with multiple values`() {
        let embeddedComma = ClientFilterToken(
            query: "",
            selectedFacets: ["skill": ["swift,ios"]],
            dateRange: nil
        )
        let separateValues = ClientFilterToken(
            query: "",
            selectedFacets: ["skill": ["swift", "ios"]],
            dateRange: nil
        )

        #expect(embeddedComma != separateValues)
    }

    @Test func `facet identifiers cannot collide with values`() {
        let delimiterInID = ClientFilterToken(
            query: "",
            selectedFacets: ["status:active": ["yes"]],
            dateRange: nil
        )
        let delimiterInValue = ClientFilterToken(
            query: "",
            selectedFacets: ["status": ["active:yes"]],
            dateRange: nil
        )

        #expect(delimiterInID != delimiterInValue)
    }
}
