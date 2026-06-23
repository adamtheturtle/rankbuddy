import SwiftUI

extension EnvironmentValues {
    // The `URLSession` HackerRank clients use. Defaults to `.shared`; demo mode swaps in
    // `URLSession.rankBuddyDemo` so views render the bundled fixtures (#10).
    @Entry var hackerRankSession: URLSession = .shared
}
