//
//  MockHackerRankURLProtocol+AuditLog.swift
//  rankbuddy-macos
//

import Foundation

extension MockHackerRankURLProtocol {
    /// The audit-log page served for `/audit_log` (#106): a deterministic change history with
    /// varied actions, source types, and a numeric `source_id` to exercise the model's
    /// string-or-number decoding. No real personal data. In a separate file so the fixture stays
    /// off the mock's file-length budget.
    nonisolated static let auditLogJSON = #"""
    {"data":[
      {"source_id":"t1","source_type":"test","action":"update",
       "user":{"firstname":"Rhea","lastname":"Recruiter","email":"rhea@example.com"},
       "modified_fields":["name","cutoff_score"],"ip_address":"203.0.113.7",
       "created_at":"2026-06-20T09:15:00Z"},
      {"source_id":"u3","source_type":"user","action":"create",
       "user":{"firstname":"Rhea","lastname":"Recruiter","email":"rhea@example.com"},
       "modified_fields":["email","role"],"ip_address":"203.0.113.7",
       "created_at":"2026-06-19T16:42:00Z"},
      {"source_id":1024,"source_type":"interview","action":"delete",
       "user":"ian@example.com","modified_fields":[],"ip_address":"198.51.100.22",
       "created_at":"2026-06-18T11:05:00Z"}
    ],"next":null}
    """#
}
