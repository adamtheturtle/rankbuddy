//
//  MockHackerRankServerTests.swift
//  rankbuddy-macosTests
//

import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for the in-process demo server (#10, #32). `URLSession.rankBuddyDemo` installs
/// `MockHackerRankURLProtocol`, which serves deterministic fixtures for the HackerRank
/// endpoints. The scenario is environment-selected and defaults to `.success`, so these
/// tests exercise the populated fixtures, the multi-page tests collection, and the path
/// routing that distinguishes a test's candidates from the tests list.
struct MockHackerRankServerTests {
    private func fetch(_ path: String) async throws -> (HTTPURLResponse, Data) {
        let url = try #require(URL(string: "https://www.hackerrank.com/x/api/v3\(path)"))
        let (data, response) = try await URLSession.rankBuddyDemo.data(from: url)
        let http = try #require(response as? HTTPURLResponse)
        return (http, data)
    }

    private func page<Item: Decodable>(_: Item.Type, _ path: String) async throws -> HackerRankPage<Item> {
        let (response, data) = try await fetch(path)
        #expect(response.statusCode == 200)
        return try JSONDecoder().decode(HackerRankPage<Item>.self, from: data)
    }

    // MARK: - Scenario selection

    @Test func `the scenario defaults to success when unset`() {
        // The test process does not set RANKBUDDY_DEMO_SCENARIO.
        #expect(MockHackerRankURLProtocol.Scenario.current == .success)
    }

    @Test func `scenario raw values map to every case`() {
        #expect(MockHackerRankURLProtocol.Scenario(rawValue: "success") == .success)
        #expect(MockHackerRankURLProtocol.Scenario(rawValue: "empty") == .empty)
        #expect(MockHackerRankURLProtocol.Scenario(rawValue: "unauthorized") == .unauthorized)
        #expect(MockHackerRankURLProtocol.Scenario(rawValue: "malformed") == .malformed)
        #expect(MockHackerRankURLProtocol.Scenario(rawValue: "throttling") == .throttled)
        #expect(MockHackerRankURLProtocol.Scenario(rawValue: "server_error") == .serverError)
        #expect(MockHackerRankURLProtocol.Scenario(rawValue: "nonsense") == nil)
    }

    // MARK: - Fixtures decode through the real models

    @Test func `the tests fixture is a multi-page collection`() async throws {
        let firstPage = try await page(Test.self, "/tests?limit=3")
        #expect(firstPage.pageItems.count == 3)
        #expect(firstPage.pageItems.first?.name == "Backend Engineer Screen")
        // The first test is organised into named sections.
        let sections = try #require(firstPage.pageItems.first?.sections)
        #expect(sections.map(\.name) == ["Coding", "Multiple Choice"])
        #expect(sections.first?.questionCount == 2)
        // The first page advertises a next page; the client follows it by offset.
        let next = try #require(firstPage.nextPage)
        #expect(next.contains("offset=3"))

        let secondPage = try await page(Test.self, "/tests?limit=3&offset=3")
        #expect(secondPage.pageItems.count == 2)
        #expect(secondPage.nextPage == nil)
    }

    @Test func `the candidates fixture includes a sparse, name-less record`() async throws {
        let candidates = try await page(TestCandidate.self, "/tests/t1/candidates")
        #expect(candidates.pageItems.count == 5)
        // c5 is the deliberately sparse fixture: only id and email.
        let sparse = try #require(candidates.pageItems.first { $0.id == "c5" })
        #expect(sparse.fullName == nil)
        #expect(sparse.score == nil)
        // A flagged candidate exercises the plagiarism badge path.
        let flagged = try #require(candidates.pageItems.first { $0.plagiarismStatus == true })
        #expect(flagged.fullName == "Grace Hopper")
    }

    @Test func `candidates routing wins over the tests path`() async throws {
        // The candidates path also contains "/tests/", so routing must check it first.
        let (_, data) = try await fetch("/tests/t1/candidates")
        let decoded = try JSONDecoder().decode(HackerRankPage<TestCandidate>.self, from: data)
        #expect(decoded.pageItems.allSatisfy { !$0.email.isEmpty })
    }

    @Test func `the questions fixture mixes code and mcq types`() async throws {
        let questions = try await page(Question.self, "/questions")
        #expect(questions.pageItems.count == 3)
        #expect(questions.pageItems.contains { $0.type == "code" })
        #expect(questions.pageItems.contains { $0.type == "mcq" })
        // Skills are surfaced in the question detail.
        let twoSum = try #require(questions.pageItems.first { $0.name == "Two Sum" })
        #expect(twoSum.skills?.contains("Problem Solving") == true)
    }

    @Test func `the interviews fixture covers completed and scheduled`() async throws {
        let interviews = try await page(Interview.self, "/interviews")
        #expect(interviews.pageItems.count == 2)
        #expect(interviews.pageItems.contains { $0.status == "completed" })
        #expect(interviews.pageItems.contains { $0.status == "scheduled" })
    }

    @Test func `the users fixture covers roles, admin flags, and a sparse record`() async throws {
        let users = try await page(User.self, "/users")
        #expect(users.pageItems.count == 4)
        let admin = try #require(users.pageItems.first { $0.companyAdmin == true })
        #expect(admin.firstName == "Rhea")
        #expect(admin.teams == ["tm1", "tm2"])
        // u4 is the sparse fixture: only id and email.
        let sparse = try #require(users.pageItems.first { $0.id == "u4" })
        #expect(sparse.firstName == nil)
        #expect(sparse.role == nil)
    }

    @Test func `the teams fixture covers member counts and a bare record`() async throws {
        let teams = try await page(Team.self, "/teams")
        #expect(teams.pageItems.count == 3)
        let staffed = try #require(teams.pageItems.first { $0.id == "tm1" })
        #expect(staffed.developerCount == 12)
        #expect(staffed.locations == ["London", "Berlin"])
        // tm3 is the bare fixture: only id and name.
        let bare = try #require(teams.pageItems.first { $0.id == "tm3" })
        #expect(bare.recruiterCount == nil)
        #expect(bare.locations == nil)
    }

    @Test func `an unknown collection serves an empty page`() async throws {
        let page = try await page(Team.self, "/leaderboards")
        #expect(page.pageItems.isEmpty)
        #expect(page.nextPage == nil)
    }
}
