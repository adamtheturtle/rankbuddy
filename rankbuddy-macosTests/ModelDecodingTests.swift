import Foundation
@testable import rankbuddy_macos
import Testing

/// Decoding coverage for the HackerRank domain models (#4), shaped to match the live
/// `/x/api/v3` responses confirmed against a real account (#3): snake_case keys, a
/// `+0000` timezone, string ids, and extra unmodelled fields that must be ignored.
struct ModelDecodingTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test func `decodes live start_time and end_time keys`() throws {
        // Regression: the live API uses start_time/end_time (not starttime/endtime).
        let json = """
        {"id":"2360707","unique_id":"31g60bhe3rg","name":"Backend Screen","state":"active",
         "start_time":"2026-06-22T04:10:51+0000","end_time":"2026-07-01T00:00:00+0000",
         "created_at":"2026-06-22T04:10:51+0000","duration":60,
         "sections":[],"permission":"owner","test_type":"coding"}
        """
        let test = try decode(Test.self, json)
        #expect(test.id == "2360707")
        #expect(test.startTime == "2026-06-22T04:10:51+0000")
        #expect(test.endTime == "2026-07-01T00:00:00+0000")
        // The display layer must render that timezone format, not fall back to raw text.
        #expect(DisplayFormat.date(test.startTime) != nil)
    }

    @Test func `candidate decodes scores, attempt times, and plagiarism`() throws {
        let json = """
        {"id":"117763483","email":"a@example.com","full_name":"A Candidate","score":74.0,
         "percentage_score":74.0,"integrity_status":"No Issues Detected","plagiarism_status":false,
         "attempt_starttime":"2026-06-22T04:56:23+0000","attempt_endtime":"2026-06-22T05:27:31+0000",
         "test":"2360707","ats_state":1,"status":7,"metadata":{},"questions":{}}
        """
        let candidate = try decode(TestCandidate.self, json)
        #expect(candidate.id == "117763483")
        #expect(candidate.score == 74.0)
        #expect(candidate.plagiarismStatus == false)
        #expect(candidate.attemptStartTime == "2026-06-22T04:56:23+0000")
    }

    @Test func `question decodes a numeric max score and ignores extra keys`() throws {
        let json = """
        {"id":"2623993","unique_id":"gr3oaq17dis","type":"code","name":"Two Sum","status":"active",
         "max_score":100.0,"recommended_duration":30,"languages":["python"],
         "skills":[],"test_case_count":12,"leaked_data":null}
        """
        let question = try decode(Question.self, json)
        #expect(question.id == "2623993")
        #expect(question.type == "code")
        #expect(question.maxScore == 100.0)
    }

    @Test func `interview decodes with a null thumbs_up`() throws {
        let json = """
        {"id":"2820015","status":"ended","url":"https://www.hackerrank.com/x/interviews/2820015",
         "title":"Pairing","created_at":"2022-03-01T21:03:04+0000","ended_at":"2022-03-01T22:43:46+0000",
         "thumbs_up":null,"interview_template_id":null,"quickpad":false,"interviewers":[]}
        """
        let interview = try decode(Interview.self, json)
        #expect(interview.id == "2820015")
        #expect(interview.status == "ended")
        #expect(interview.thumbsUp == nil)
    }
}
