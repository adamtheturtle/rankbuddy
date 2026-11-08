//
//  TemplateQuestionEditorModel.swift
//  rankbuddy-macos
//

import Foundation
import HackerRankKit
import Observation

@Observable
final class TemplateQuestionEditorModel {
    private(set) var record: TemplateRecord
    private(set) var availableQuestions: [Question] = []
    private(set) var nextCursor: String?
    private(set) var totalCount: Int?
    private(set) var didLoadQuestions = false
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var needsRefresh = true
    var errorMessage: String?
    var query = ""
    private let client: HackerRankClient

    init(record: TemplateRecord, client: HackerRankClient) {
        self.record = record
        self.client = client
    }

    var canEdit: Bool {
        record.kind == .interview && record.editorAccess == true
            && record.apiID.flatMap(Int.init) != nil && record.questionIDs != nil
            && !isSaving && !needsRefresh
    }

    var candidates: [Question] {
        let existing = Set(record.questionIDs ?? [])
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return availableQuestions.filter {
            !existing.contains($0.id) && (search.isEmpty || $0.name.localizedStandardContains(search))
        }
    }

    @discardableResult
    func refresh() async -> Bool {
        do {
            let fresh = try await TemplateLibrary.detail(record, client: client)
            try Task.checkCancellation()
            guard fresh.apiID == record.apiID, fresh.questionIDs != nil else {
                errorMessage = "The template response did not include the expected question membership."
                return false
            }

            record = fresh
            needsRefresh = false
            errorMessage = nil
            return true
        } catch {
            guard !Task.isCancelled else { return false }

            errorMessage = rankCoverageError(error)
            return false
        }
    }

    func loadMore() async {
        guard !isLoading, !didLoadQuestions || nextCursor != nil else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            guard let page = try await ListPageLoading.load({ try await client.questionsPage(after: nextCursor) })
            else { return }

            if page.next != nil, page.next == nextCursor {
                errorMessage = "The question library repeated a page. Try again."
                return
            }
            availableQuestions = ListPageMerge.merge(availableQuestions, with: page.items)
            nextCursor = page.next
            totalCount = page.totalCount
            didLoadQuestions = true
        } catch {
            errorMessage = rankCoverageError(error)
        }
    }

    func searchMore() async {
        var pages = 0
        while !Task.isCancelled, candidates.isEmpty, !didLoadQuestions || nextCursor != nil, pages < 32 {
            let before = nextCursor
            await loadMore()
            pages += 1
            if nextCursor == before {
                break
            }
        }
    }

    func add(_ question: Question) async {
        guard canEdit, let templateID = record.apiID.flatMap(Int.init),
              let questionID = Int(question.id), !(record.questionIDs ?? []).contains(question.id) else { return }

        await change {
            _ = try await client.addQuestionsToInterviewTemplate(id: templateID, questionIDs: [questionID])
        }
    }

    func remove(_ questionID: String) async {
        guard canEdit, let templateID = record.apiID.flatMap(Int.init),
              let numericID = Int(questionID), (record.questionIDs ?? []).contains(questionID) else { return }

        await change {
            _ = try await client.removeQuestionFromInterviewTemplate(id: templateID, questionID: numericID)
        }
    }

    private func change(_ operation: () async throws -> Void) async {
        isSaving = true
        errorMessage = nil
        needsRefresh = true
        defer { isSaving = false }
        do {
            try await operation()
        } catch {
            errorMessage = rankCoverageError(error)
            return
        }
        if await !refresh() {
            errorMessage = "The change was saved, but the template could not be refreshed. "
                + "Refresh before making another change."
        }
    }
}
