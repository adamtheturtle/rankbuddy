//
//  ApplicationStartupTests.swift
//  rankbuddy-macosTests
//

@testable import rankbuddy_macos
import Testing

struct ApplicationStartupTests {
    @Test func `startup gate permits exactly one launch`() {
        var gate = ApplicationStartupGate()

        #expect(gate.claim())
        #expect(!gate.claim())
        #expect(!gate.claim())
    }
}
