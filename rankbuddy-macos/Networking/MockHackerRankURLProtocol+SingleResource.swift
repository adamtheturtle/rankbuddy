//
//  MockHackerRankURLProtocol+SingleResource.swift
//  rankbuddy-macos
//

import Foundation

extension MockHackerRankURLProtocol {
    /// The richer single-test read served for `/tests/{id}` (#105): candidate login links, the
    /// (sensitive) shared access password, and MCQ scoring over the list shape. In a separate
    /// file so the fixtures stay off the mock's file-length budget.
    nonisolated static let testDetailJSON = #"""
    {"id":"t1","unique_id":"backend-screen","name":"Backend Engineer Screen","state":"active",
     "duration":90,"languages":["python","go","java"],"cutoff_score":70,
     "short_login_url":"https://hr.gs/backend-screen",
     "public_login_url":"https://www.hackerrank.com/tests/backend-screen/login",
     "master_password":"demo-master-pw","mcq_correct_score":4.0,"mcq_incorrect_score":-1.0}
    """#

    /// The richer single-question read served for `/questions/{id}` (#105): MCQ options, the
    /// (sensitive) correct answer, and internal notes over the list shape.
    nonisolated static let questionDetailJSON = #"""
    {"id":"q3","unique_id":"sql-joins","type":"mcq","name":"SQL Joins","status":"published",
     "max_score":50.0,"recommended_duration":10,"tags":["sql"],
     "options":["INNER JOIN","LEFT JOIN","RIGHT JOIN","FULL OUTER JOIN"],
     "answer":"INNER JOIN","internal_notes":"Swap in a CROSS JOIN distractor next revision."}
    """#
}
