//
//  SearchInterpreter.swift
//  rankbuddy-macos
//
//  On-device natural-language smart search (#91). Turns a request like "python questions from
//  last week" or "failed candidates" into the structured filters a `LoadableList` already
//  applies — free-text query, the date-range chip, and the declared facets (state, window,
//  language, role, tags…) — using Apple's on-device FoundationModels. It's the inverse of the
//  saved-search namer: words → filters. On-device only, additive, and a no-op (filters
//  untouched) when the model is unavailable or it can't ground anything. Mirrors PadBuddy's
//  `SearchInterpreter`.
//

import Foundation
import FoundationModels

enum SearchInterpreter {
    /// A facet the list filters on, paired with the distinct values actually present, so the
    /// model maps onto real options rather than inventing them.
    struct FacetDescriptor: Sendable {
        let id: String
        let label: String
        let options: [String]
    }

    /// The structured filters derived from a query: the free-text keywords, an optional named
    /// date range, and the chosen values per facet id. Empty/`nil`/`[:]` when nothing applies.
    struct Interpretation: Sendable, Equatable {
        var query: String
        var dateRange: String?
        var facets: [String: Set<String>]

        /// Whether this would actually change the list — an interpretation that grounds to
        /// nothing leaves the filters alone and tells the user nothing matched.
        var isEmpty: Bool {
            query.isEmpty && dateRange == nil && facets.values.allSatisfy(\.isEmpty)
        }
    }

    /// Whether the on-device model can interpret a query right now, so the affordance can be
    /// hidden otherwise.
    static var isAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Interprets `text` into grounded filters, or `nil` when the model is unavailable, the
    /// text is empty, generation fails, or nothing grounded. The returned values are always a
    /// subset of the real options the list offers.
    static func interpret(
        _ text: String,
        facets: [FacetDescriptor],
        dateRangeSupported: Bool,
        dateRangeOptions: [String]
    ) async -> Interpretation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAvailable, !trimmed.isEmpty else { return nil }

        let session = LanguageModelSession(instructions: instructions)
        let prompt = prompt(for: trimmed, facets: facets, dateRangeSupported: dateRangeSupported, dateRangeOptions: dateRangeOptions)
        do {
            let raw = try await session.respond(to: prompt, generating: ModelInterpretation.self).content
            let grounded = ground(
                raw,
                query: trimmed,
                facets: facets,
                dateRangeSupported: dateRangeSupported,
                dateRangeOptions: dateRangeOptions
            )
            return grounded.isEmpty ? nil : grounded
        } catch {
            return nil
        }
    }

    // MARK: - Prompt

    /// The instructions that set the model's job and guardrails for every interpretation.
    private static let instructions = """
    You convert a recruiter's plain-language request into structured list filters. Only use the \
    facet values and date ranges offered to you; never invent values. Put genuine topic words \
    (a question or test name) in "keywords" and leave everything that maps to a facet or date \
    out of it. If part of the request doesn't map to anything offered, omit it.
    """

    private static func prompt(
        for text: String,
        facets: [FacetDescriptor],
        dateRangeSupported: Bool,
        dateRangeOptions: [String]
    ) -> String {
        var lines = ["Request: \(text)", "", "Available facets (use only these exact values):"]
        if facets.isEmpty {
            lines.append("- (none)")
        } else {
            for facet in facets {
                let options = optionList(facet.options, limit: optionLimit)
                lines.append("- \(facet.id) (\(facet.label)): \(options.isEmpty ? "(no values)" : options)")
            }
        }
        if dateRangeSupported {
            lines.append("")
            lines.append("Available date ranges: \(optionList(dateRangeOptions, limit: optionLimit))")
        }
        lines.append("")
        lines.append(
            """
            Respond with: keywords (topic words only, may be empty); dateRange (one of the ranges \
            above or empty); filters as lines "facetId=value", one per chosen value (may be empty).
            """
        )
        return lines.joined(separator: "\n")
    }

    /// A short, comma-separated option list to steer the model, capped so a big org's value
    /// list can't dominate the prompt.
    static func optionList(_ values: [String], limit: Int) -> String {
        values.prefix(limit).joined(separator: ", ")
    }

    private static let optionLimit = 40

    // MARK: - Grounding (pure, unit-tested)

    /// Vets the model's raw fields against the query and the real options: keeps only values the
    /// query actually supports, so the small model's habit of over-filling fields can't
    /// over-constrain the list to nothing.
    static func ground(
        _ raw: ModelInterpretation,
        query: String,
        facets: [FacetDescriptor],
        dateRangeSupported: Bool,
        dateRangeOptions: [String]
    ) -> Interpretation {
        var facetSelections: [String: Set<String>] = [:]
        let facetsByID = Dictionary(uniqueKeysWithValues: facets.map { ($0.id, $0) })
        var facetValueWords: Set<String> = []
        for (facetID, value) in parseFilters(raw.filters) {
            guard let facet = facetsByID[facetID],
                  let option = groundFacetValue(value, facetOptions: facet.options, query: query)
            else { continue }

            facetSelections[facetID, default: []].insert(option)
            facetValueWords.formUnion(tokens(option))
        }

        let dateRange = dateRangeSupported
            ? groundDateRange(resolveDateRange(raw.dateRange, options: dateRangeOptions), query: query)
            : nil

        let groundedQuery = groundText(raw.keywords, facetValueWords: facetValueWords)
        return Interpretation(query: groundedQuery, dateRange: dateRange, facets: facetSelections)
    }

    /// Parses the model's `filters` block ("facetId=value" lines) into pairs, tolerating commas,
    /// semicolons, or newlines between entries and stray surrounding whitespace.
    static func parseFilters(_ raw: String) -> [(facetID: String, value: String)] {
        raw
            .split(whereSeparator: { $0 == "\n" || $0 == ";" })
            .compactMap { entry in
                let parts = entry.split(separator: "=", maxSplits: 1)
                guard parts.count == 2 else { return nil }

                let id = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, !value.isEmpty else { return nil }

                return (id, value)
            }
    }

    /// Keeps a model-proposed facet value only when it matches a real option (case-insensitive)
    /// *and* the query mentions a word of that option — so the model can't attach an option the
    /// request never named. Returns the option in its canonical casing.
    static func groundFacetValue(_ value: String, facetOptions: [String], query: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty,
              let option = facetOptions.first(where: { $0.lowercased() == trimmed })
        else { return nil }

        let optionWords = tokens(option).filter { $0.count >= 2 }
        guard !optionWords.isEmpty else { return nil }

        return tokens(query).isDisjoint(with: optionWords) ? nil : option
    }

    /// Matches a free-form range onto one of the offered options, case-insensitively. Nil when
    /// unrecognized.
    static func resolveDateRange(_ raw: String, options: [String]) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        return options.first { $0.lowercased() == trimmed }
    }

    /// Keeps a resolved date window only when the query mentions a time frame, so the model can't
    /// attach a range the request never implied.
    static func groundDateRange(_ range: String?, query: String) -> String? {
        guard let range else { return nil }

        let dateWords: Set<String> = [
            "today", "yesterday", "week", "weeks", "month", "months", "day", "days",
            "hour", "hours", "recent", "recently", "last", "past", "this",
            "24", "7", "30", "90", "year", "years"
        ]
        return tokens(query).isDisjoint(with: dateWords) ? nil : range
    }

    /// Strips the model's free-text down to genuine title keywords: drops filter stop-words and
    /// every word of a matched facet value, so a query the model echoes wholesale collapses to
    /// the real topic (or empty) and the structured filters do the work.
    static func groundText(_ raw: String, facetValueWords: Set<String>) -> String {
        let drop = filterStopWords.union(facetValueWords)
        let kept = raw
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init)
            .filter { word in
                let key = word.lowercased().filter { $0.isLetter || $0.isNumber }
                return !key.isEmpty && !drop.contains(key)
            }
        return kept.joined(separator: " ")
    }

    /// Lowercased alphanumeric word tokens of `text`, for whole-word comparison (so "lin" doesn't
    /// match inside "linked").
    static func tokens(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { !$0.isEmpty }
        )
    }

    /// Words that name a filter concept rather than a list-item title, so they must never survive
    /// into the free-text search.
    static let filterStopWords: Set<String> = [
        "test", "tests", "question", "questions", "interview", "interviews", "candidate",
        "candidates", "user", "users", "team", "teams",
        "by", "from", "the", "a", "an", "of", "in", "on", "for", "with", "and", "or",
        "my", "me", "mine", "show", "find", "all", "owned", "created", "made", "that", "are",
        "today", "yesterday", "last", "recent", "recently", "past", "this",
        "day", "days", "week", "weeks", "month", "months", "hour", "hours", "year", "years"
    ]
}

/// The fixed schema the on-device model fills. Dynamic per-facet selections ride in `filters`
/// as "facetId=value" lines, which `SearchInterpreter.ground` parses and vets — so one stable
/// `@Generable` shape covers any list's facets.
@Generable
struct ModelInterpretation: Equatable {
    @Guide(description: "Genuine topic words from the request (a question or test name). Empty if none.")
    var keywords: String

    @Guide(description: "One of the offered date ranges that matches the request, or empty.")
    var dateRange: String

    @Guide(description: "Chosen facet values as lines 'facetId=value', one per value. Empty if none.")
    var filters: String
}
