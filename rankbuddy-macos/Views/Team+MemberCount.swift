//
//  Team+MemberCount.swift
//  rankbuddy-macos
//

import HackerRankKit

extension Team {
    /// Total membership represented by the API's role counts, or nil when none are known.
    var knownMemberCount: Int? {
        let counts = [recruiterCount, developerCount, interviewerCount].compactMap(\.self)
        return counts.isEmpty ? nil : counts.reduce(0, +)
    }
}
