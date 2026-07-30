//
//  WhatsNew.swift
//  rankbuddy-macos
//

import Foundation
import WhatsNewKit

/// The current release notes. WhatsNewKit owns version gating and persistence, matching PadBuddy.
enum WhatsNewContent {
    static let featureCount = 4

    static let current = WhatsNew(
        version: .current(),
        title: .init(text: .init(String(localized: "What's New in RankBuddy"))),
        features: [
            .init(
                image: .init(systemName: "line.3.horizontal.decrease.circle"),
                title: .init(String(localized: "Filter & save searches")),
                subtitle: .init(String(localized:
                    "Narrow any list by date range, then save a search to re-run it later."))
            ),
            .init(
                image: .init(systemName: "square.and.arrow.up"),
                title: .init(String(localized: "Print & export")),
                subtitle: .init(String(localized:
                    "Print or save a candidate report as PDF, and export any list to CSV."))
            ),
            .init(
                image: .init(systemName: "bell.badge"),
                title: .init(String(localized: "Stay in the loop")),
                subtitle: .init(String(localized:
                    "An optional Dock badge of upcoming interviews, with notifications for new ones."))
            ),
            .init(
                image: .init(systemName: "macwindow"),
                title: .init(String(localized: "More at home on the Mac")),
                subtitle: .init(String(localized:
                    "A welcome screen, relative dates, theme options, and a Dock menu."))
            )
        ],
        primaryAction: .init(title: .init(String(localized: "Continue")))
    )
}
