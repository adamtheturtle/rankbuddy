//
//  MockHackerRankURLProtocol+Interview.swift
//  rankbuddy-macos
//

import Foundation

extension MockHackerRankURLProtocol {
    /// Routes a single-interview read (#103) to its fixture — the transcript or the detail — or
    /// `nil` for the bare `/interviews` collection so the caller serves the list. In a separate
    /// file so the fixtures stay off the mock's file- and type-body-length budgets.
    nonisolated static func interviewSingleBody(path: String) -> String? {
        if path.hasSuffix("/transcript") {
            return interviewTranscriptJSON
        }
        if !path.hasSuffix("/interviews") {
            return interviewDetailJSON
        }
        return nil
    }

    /// The richer single-interview read served for `/interviews/{id}` (#103): the additive detail
    /// fields (scheduled window, interviewers, owner, candidate, links) over the list shape.
    nonisolated static let interviewDetailJSON = #"""
    {"id":"i1","status":"completed","url":"https://www.hackerrank.com/x/interviews/i1",
     "title":"Senior Backend — Pairing","created_at":"2026-05-05T13:00:00Z",
     "ended_at":"2026-05-05T14:00:00Z","thumbs_up":1,"feedback":"Strong system design.",
     "report_url":"https://www.hackerrank.com/x/interviews/i1/report",
     "from":"2026-05-05T13:00:00Z","to":"2026-05-05T14:00:00Z",
     "resume_url":"https://www.hackerrank.com/x/interviews/i1/resume",
     "result_url":"https://www.hackerrank.com/x/interviews/i1/result",
     "user":{"firstname":"Rhea","lastname":"Recruiter","email":"rhea@example.com"},
     "candidate":{"firstname":"Ada","lastname":"Lovelace","email":"ada@example.com"},
     "interviewers":[{"firstname":"Ian","lastname":"Interviewer","email":"ian@example.com"},
                     {"firstname":"Rhea","lastname":"Recruiter","email":"rhea@example.com"}]}
    """#

    /// The conversation transcript served for `/interviews/{id}/transcript` (#103). Deterministic
    /// demo dialogue — no real personal data; the pad's source code is not part of the transcript.
    nonisolated static let interviewTranscriptJSON = #"""
    {"messages":[
      {"messageId":"m1","author":"Ian Interviewer","email":"ian@example.com","candidate":false,
       "timestamp":1746450000,"text":"Welcome! Let's start with a brief warm-up question."},
      {"messageId":"m2","author":"Ada Lovelace","email":"ada@example.com","candidate":true,
       "timestamp":1746450060,"text":"Sounds good — I'm ready when you are."},
      {"messageId":"m3","author":"Ian Interviewer","email":"ian@example.com","candidate":false,
       "timestamp":1746450120,"text":"Great. Can you walk me through your approach?"}
    ]}
    """#
}
