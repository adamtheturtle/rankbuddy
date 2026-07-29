//
//  HackerRankDetailMetadata.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit

/// Fetches the standard metadata fields that HackerRank's list endpoints may omit but the
/// corresponding detail endpoint can return. HackerRankKit's detail models intentionally expose
/// only the endpoint-specific extras, so the app keeps this tiny overlay local to its detail views.
nonisolated struct HackerRankDetailMetadataClient {
    let account: Account

    func question(id: String) async throws -> QuestionDetailMetadata? {
        guard !account.isMock else { return nil }

        return try await fetch(QuestionDetailMetadata.self, collection: "questions", id: id)
    }

    func test(id: String) async throws -> TestDetailMetadata? {
        guard !account.isMock else { return nil }

        return try await fetch(TestDetailMetadata.self, collection: "tests", id: id)
    }

    private func fetch<Value: Decodable>(_: Value.Type, collection: String, id: String) async throws -> Value {
        let path = "/x/api/v3/\(collection)/\(Self.pathSegment(id))"
        guard let url = URL(string: path, relativeTo: account.baseURL)?.absoluteURL else {
            throw HackerRankError.network(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(account.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200 ... 299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HackerRankError.http(http.statusCode, body)
        }

        return try HackerRankClient.makeDecoder().decode(Value.self, from: data)
    }

    private static func pathSegment(_ raw: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? raw
    }
}

nonisolated struct QuestionDetailMetadata: Decodable {
    var uniqueID: String?
    var type: String?
    var name: String?
    var owner: String?
    var createdAt: String?
    var status: String?
    var languages: [String]?
    var problemStatement: String?
    var recommendedDuration: Int?
    var tags: [String]?
    var maxScore: Double?
    var skills: [String]?

    enum CodingKeys: String, CodingKey {
        case uniqueID = "unique_id"
        case type
        case name
        case owner
        case createdAt = "created_at"
        case status
        case languages
        case problemStatement = "problem_statement"
        case recommendedDuration = "recommended_duration"
        case tags
        case maxScore = "max_score"
        case skills
    }

    func applying(to question: Question) -> Question {
        Question(
            id: question.id,
            uniqueID: uniqueID ?? question.uniqueID,
            type: type ?? question.type,
            name: name ?? question.name,
            owner: owner ?? question.owner,
            createdAt: createdAt ?? question.createdAt,
            status: status ?? question.status,
            languages: languages ?? question.languages,
            problemStatement: problemStatement ?? question.problemStatement,
            recommendedDuration: recommendedDuration ?? question.recommendedDuration,
            tags: tags ?? question.tags,
            maxScore: maxScore ?? question.maxScore,
            skills: skills ?? question.skills
        )
    }
}

nonisolated struct TestDetailMetadata: Decodable {
    var uniqueID: String?
    var name: String?
    var startTime: String?
    var endTime: String?
    var duration: Int?
    var owner: String?
    var instructions: String?
    var starred: Bool?
    var createdAt: String?
    var state: String?
    var locked: Bool?
    var draft: Bool?
    var languages: [String]?
    var cutoffScore: Int?
    var tags: [String]?
    var library: String?
    var role: String?
    var skills: [String]?
    var type: String?
    var questions: [String]?
    var shuffleQuestions: Bool?
    var enableProctoring: Bool?
    var sections: [TestSection]?

    enum CodingKeys: String, CodingKey {
        case uniqueID = "unique_id"
        case name
        case startTime = "start_time"
        case endTime = "end_time"
        case duration
        case owner
        case instructions
        case starred
        case createdAt = "created_at"
        case state
        case locked
        case draft
        case languages
        case cutoffScore = "cutoff_score"
        case tags
        case library
        case role
        case skills
        case type
        case questions
        case shuffleQuestions = "shuffle_questions"
        case enableProctoring = "enable_proctoring"
        case sections
    }

    func applying(to test: Test) -> Test {
        Test(
            id: test.id,
            uniqueID: uniqueID ?? test.uniqueID,
            name: name ?? test.name,
            startTime: startTime ?? test.startTime,
            endTime: endTime ?? test.endTime,
            duration: duration ?? test.duration,
            owner: owner ?? test.owner,
            instructions: instructions ?? test.instructions,
            starred: starred ?? test.starred,
            createdAt: createdAt ?? test.createdAt,
            state: state ?? test.state,
            locked: locked ?? test.locked,
            draft: draft ?? test.draft,
            languages: languages ?? test.languages,
            cutoffScore: cutoffScore ?? test.cutoffScore,
            tags: tags ?? test.tags,
            library: library ?? test.library,
            role: role ?? test.role,
            skills: skills ?? test.skills,
            type: type ?? test.type,
            questions: questions ?? test.questions,
            shuffleQuestions: shuffleQuestions ?? test.shuffleQuestions,
            enableProctoring: enableProctoring ?? test.enableProctoring,
            sections: sections ?? test.sections
        )
    }
}
