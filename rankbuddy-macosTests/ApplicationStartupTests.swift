//
//  ApplicationStartupTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

struct ApplicationStartupTests {
    @Test func `startup gate permits exactly one launch`() {
        var gate = ApplicationStartupGate()
        let first = gate.claim()
        let second = gate.claim()
        let third = gate.claim()

        #expect(first)
        #expect(!second)
        #expect(!third)
    }
}
