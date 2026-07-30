//
//  SpotlightKeywords.swift
//  rankbuddy-macos
//
//  On-device keyword enrichment for the Spotlight index (#92). Rides entirely on top of the
//  existing #24 indexing: nothing new is indexed, the keywords just enrich the items already
//  donated (tests, questions, interviews) so Spotlight surfaces them for topical terms that
//  don't appear verbatim in the title. On-device only (FoundationModels), additive, and a
//  no-op when the model is unavailable. Mirrors PadBuddy's `SpotlightSummarizer`.
//

import AppIntents
import BuddyAppKit
import CoreSpotlight
import Foundation
import HackerRankKit
import os

/// A donated entity paired with the on-device text its keywords are generated from. The source
/// text is never indexed or returned to the system — only the short keywords derived from it
/// are — so report contents and PII never enter the index (the #24 privacy allowlist holds).
struct EnrichableEntity {
    let entity: RankBuddyObjectEntity
    /// The brief fed to the on-device model, or empty when the item has nothing beyond its
    /// title worth summarising (so a bare item never burns a generation).
    let keywordSource: String
}

/// Builds the on-device text a RankBuddy object's Spotlight keywords are generated from (#92).
///
/// Pure and deterministic (unit-tested): it assembles the list fields RankBuddy *already*
/// fetched — names, tags, skills, and languages — into a compact brief. Free-text problem,
/// instruction, and interview-note fields are deliberately excluded because they can contain
/// candidate PII. Returns `nil` when there isn't
/// enough beyond the title to be worth a model call.
enum SpotlightKeywordSource {
    static func text(for test: Test) -> String? {
        var parts = ["Name: \(visibleText(test.name))"]
        var hasSubstance = false
        if let tags = cleaned(test.tags), !tags.isEmpty {
            parts.append("Tags: \(tags.joined(separator: ", "))")
            hasSubstance = true
        }
        if let languages = cleaned(test.languages), !languages.isEmpty {
            parts.append("Languages: \(languages.joined(separator: ", "))")
            hasSubstance = true
        }
        return hasSubstance ? parts.joined(separator: "\n") : nil
    }

    static func text(for question: Question) -> String? {
        var parts = ["Title: \(visibleText(question.name))"]
        var hasSubstance = false
        if let tags = cleaned(question.tags), !tags.isEmpty {
            parts.append("Tags: \(tags.joined(separator: ", "))")
            hasSubstance = true
        }
        if let skills = cleaned(question.skills), !skills.isEmpty {
            parts.append("Skills: \(skills.joined(separator: ", "))")
            hasSubstance = true
        }
        if let languages = cleaned(question.languages), !languages.isEmpty {
            parts.append("Languages: \(languages.joined(separator: ", "))")
            hasSubstance = true
        }
        return hasSubstance ? parts.joined(separator: "\n") : nil
    }

    static func text(for _: Interview) -> String? {
        nil
    }

    private static func cleaned(_ values: [String]?) -> [String]? {
        values?.map(visibleText).filter { !$0.isEmpty }
    }

    private static func visibleText(_ value: String) -> String {
        MarkdownExport.plainText(fromHTML: value)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// The on-device enricher (#92). Generates a few topical keywords per item from its brief and
/// re-indexes the same entity ids with them attached. Strictly on-device, additive, bounded per
/// pass, and a graceful no-op when Apple's on-device model is unavailable.
@MainActor
enum SpotlightKeywordEnricher {
    /// Whether the on-device model is ready, so the pass is skipped entirely otherwise.
    static var isAvailable: Bool {
        SpotlightKeywordGenerator.isAvailable
    }

    /// How many items one pass will enrich. Each enrichment runs the language model, so a big
    /// org's full list would be far too costly in one go; the cap keeps it bounded and the
    /// dropped remainder is logged rather than silently skipped.
    private static let maxEnrichmentsPerPass = 50

    /// Entity ids enriched (or attempted) this process, so repeated suggestion requests don't
    /// re-run the model over items already covered.
    private static var enrichedIDs: Set<String> = []
    /// Guards against overlapping passes when the system asks for suggestions in quick succession.
    private static var isEnriching = false

    private static let logger = Logger(subsystem: "com.adamdangoor.rankbuddy", category: "spotlight")

    /// Enriches a bounded set of the donated entities with on-device keywords and re-indexes
    /// them. Re-indexing reuses each entity's id, so it updates the existing Spotlight item in
    /// place rather than adding a duplicate.
    static func enrich(_ enrichables: [EnrichableEntity]) async {
        guard isAvailable, !isEnriching else { return }

        let pending = enrichables.filter { !$0.keywordSource.isEmpty && !enrichedIDs.contains($0.entity.id) }
        guard !pending.isEmpty else { return }

        let bounded = Array(pending.prefix(maxEnrichmentsPerPass))
        if pending.count > bounded.count {
            logger.info(
                """
                Spotlight keyword enrichment limited to \
                \(maxEnrichmentsPerPass, privacy: .public) of \
                \(pending.count, privacy: .public) items this pass
                """
            )
        }

        isEnriching = true
        defer { isEnriching = false }

        let index = CSSearchableIndex(name: RankBuddySpotlightIndex.name)
        for enrichable in bounded {
            // Record the attempt up front so a no-keyword or failed item isn't retried forever.
            enrichedIDs.insert(enrichable.entity.id)
            let keywords = await SpotlightKeywordGenerator.keywords(from: enrichable.keywordSource)
            guard !keywords.isEmpty else { continue }

            var entity = enrichable.entity
            entity.keywords = keywords
            try? await index.indexAppEntities([entity])
        }
    }
}
