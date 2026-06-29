//
//  MockHackerRankURLProtocol+Search.swift
//  rankbuddy-macos
//

import Foundation

extension MockHackerRankURLProtocol {
    /// Serves the server-side search endpoints (`/users/search`, `/tests/{id}/candidates/search`,
    /// #104) so the demo actually narrows as you type. Picks the fixture by path, then filters its
    /// `data` rows to those with any string value containing the `search` term (case-insensitive) —
    /// a faithful stand-in for the server's own matching. An empty term returns the whole fixture.
    nonisolated static func searchBody(for url: URL) -> String {
        let term = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "search" }?.value ?? ""
        let base = url.path.contains("/candidates") ? candidateSearchJSON : userSearchJSON
        let needle = term.lowercased()
        guard !needle.isEmpty,
              let data = base.data(using: .utf8),
              var envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = envelope["data"] as? [[String: Any]] else {
            return base
        }

        let matched = rows.filter { row in
            row.values.contains { ($0 as? String)?.lowercased().contains(needle) == true }
        }
        envelope["data"] = matched
        guard let out = try? JSONSerialization.data(withJSONObject: envelope),
              let json = String(bytes: out, encoding: .utf8) else { return base }

        return json
    }

    /// Users the demo "user search" matches over. A small, sanitized set distinct enough that a
    /// query visibly narrows it.
    private nonisolated static let userSearchJSON = #"""
    {"data":[
      {"id":"u1","email":"rhea@example.com","firstname":"Rhea","lastname":"Recruiter",
       "country":"GB","role":"recruiter","status":"active"},
      {"id":"u2","email":"ian@example.com","firstname":"Ian","lastname":"Interviewer",
       "country":"DE","role":"interviewer","status":"active"},
      {"id":"u3","email":"pat@example.com","firstname":"Pat","lastname":"Pending",
       "country":"US","role":"recruiter","status":"invited"}
    ],"next":null}
    """#

    /// Candidates the demo "candidate search" matches over.
    private nonisolated static let candidateSearchJSON = #"""
    {"data":[
      {"id":"c1","email":"ada@example.com","full_name":"Ada Lovelace","score":92.0,
       "percentage_score":92.0,"integrity_status":"clean","status":7,"ats_state":2,
       "attempt_starttime":"2026-05-02T10:00:00Z","attempt_endtime":"2026-05-02T11:15:00Z"},
      {"id":"c3","email":"grace@example.com","full_name":"Grace Hopper","score":58.0,
       "percentage_score":58.0,"integrity_status":"review","plagiarism_status":true,
       "status":7,"ats_state":22,"attempt_starttime":"2026-05-04T08:30:00Z"}
    ],"next":null}
    """#
}
