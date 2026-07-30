//
//  PrintableReports.swift
//  rankbuddy-macos
//

import BuddyDesignSystem
import HackerRankKit
import PrintableView
import SwiftUI

// Print / Save-as-PDF support for the read-only detail views (#13), built on buddy-kit
// 0.7.0's `DocumentPrinter`. Each report is a clean, document-shaped view (rather than the
// on-screen grouped `Form`) so it rasterizes and paginates well on paper. Keeping the
// `printDocument` call and the `PrintSection` layout here means the detail views only need
// to drop in a `PrintReportButton`.

@MainActor
func printReport(_ report: some View, jobTitle: String) {
    printDocument(report, jobTitle: jobTitle)
}

/// A toolbar button that prints (or saves as PDF) the supplied report, bound to ⌘P.
struct PrintReportButton<Report: View>: View {
    let jobTitle: String
    @ViewBuilder let report: () -> Report

    var body: some View {
        Button {
            printReport(report(), jobTitle: jobTitle)
        } label: {
            Label("Print…", systemImage: "printer")
        }
        .keyboardShortcut("p", modifiers: .command)
        .help("Print or save as PDF")
    }
}

// MARK: - Shared layout

/// One label/value line in a report.
private struct ReportField: Identifiable {
    let id: Int
    let label: String
    let value: String
}

/// Builds report fields from `(label, value?)` pairs, dropping any with no value.
private func reportFields(_ pairs: [(String, String?)]) -> [ReportField] {
    pairs.enumerated().compactMap { index, pair in
        pair.1.map { ReportField(id: index, label: pair.0, value: $0) }
    }
}

/// A column of label/value lines.
private struct ReportFieldList: View {
    let fields: [ReportField]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(fields) { field in
                HStack(alignment: .top, spacing: 8) {
                    Text(field.label)
                        .foregroundStyle(.secondary)
                        .frame(width: 140, alignment: .leading)
                    Text(field.value)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// A document shell: a titled header over the supplied sections, padded for print margins.
private struct ReportDocument<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title2).bold()
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }
}

// MARK: - Candidate report (#13)

/// A printable candidate report: identity, scores, pipeline state, proctoring, and feedback.
struct CandidateReport: View {
    let candidate: TestCandidate

    var body: some View {
        ReportDocument(title: candidate.fullName ?? candidate.email, subtitle: "HackerRank Candidate Report") {
            PrintSection(title: "Candidate") {
                ReportFieldList(fields: reportFields([
                    ("Name", candidate.fullName),
                    ("Email", candidate.email),
                    ("Attempt", candidate.attemptStatusLabel),
                    ("Pipeline", candidate.pipelineStatusLabel),
                    ("Score", candidate.score.map { $0.formatted() }),
                    ("Percentage", candidate.percentageScore.map { "\($0.formatted())%" }),
                    ("Integrity", candidate.integrityStatus),
                    ("Plagiarism", candidate.plagiarismStatus.map { $0 ? "Flagged" : "Clear" }),
                    ("Started", DisplayFormat.date(candidate.attemptStartTime)),
                    ("Ended", DisplayFormat.date(candidate.attemptEndTime)),
                    ("Time taken", DisplayFormat.duration(
                        fromISO: candidate.attemptStartTime, toISO: candidate.attemptEndTime
                    ))
                ]))
            }

            if candidate.hasProctoringSignals {
                PrintSection(title: "Proctoring") {
                    ReportFieldList(fields: reportFields([
                        ("Left test window", candidate.outOfWindowEvents.map { "\($0)×" }),
                        ("Time outside window", DisplayFormat.interval(candidate.outOfWindowDuration)),
                        ("Editor pastes", candidate.editorPasteCount.map { "\($0)×" })
                    ]))
                }
            }

            if let tags = candidate.tags, !tags.isEmpty {
                PrintSection(title: "Tags") { Text(tags.joined(separator: ", ")) }
            }

            if let feedback = candidate.feedback, !feedback.isEmpty {
                PrintSection(title: "Feedback") { Text(feedback) }
            }
        }
    }
}

// MARK: - Test report

/// A printable test report: configuration, sections, tags, and instructions.
struct TestReport: View {
    let data: TestReportData

    var body: some View {
        let test = data.test
        ReportDocument(title: test.name, subtitle: "HackerRank Test Report") {
            PrintSection(title: "Test") {
                ReportFieldList(fields: reportFields([
                    ("State", DisplayFormat.enumLabel(test.state)),
                    ("Unique ID", test.uniqueID),
                    ("Duration", test.duration.map { "\($0) min" }),
                    ("Cutoff score", test.cutoffScore.map(String.init)),
                    ("Questions", test.questions.map { "\($0.count)" }),
                    ("Starts", DisplayFormat.date(test.startTime)),
                    ("Ends", DisplayFormat.date(test.endTime)),
                    ("Created", DisplayFormat.date(test.createdAt)),
                    ("Library", DisplayFormat.list(test.libraryFilterValues)),
                    ("Role", DisplayFormat.list(test.roleFilterValues)),
                    ("Skills", DisplayFormat.list(test.skillFilterValues)),
                    ("Type", DisplayFormat.list(test.typeFilterValues)),
                    ("Languages", DisplayFormat.languages(test.languages)),
                    ("Proctoring", test.enableProctoring.map { $0 ? "Enabled" : "Disabled" }),
                    ("Shuffle questions", DisplayFormat.boolean(test.shuffleQuestions)),
                    ("Starred", DisplayFormat.boolean(test.starred)),
                    ("Locked", DisplayFormat.boolean(test.locked)),
                    ("Draft", DisplayFormat.boolean(test.draft)),
                    ("MCQ correct score", data.mcqCorrectScore.map { $0.formatted() }),
                    ("MCQ incorrect score", data.mcqIncorrectScore.map { $0.formatted() })
                ]))
            }

            let accessFields = reportFields([
                ("Short login URL", data.shortLoginURL),
                ("Public login URL", data.publicLoginURL),
                ("Access password", data.accessPassword)
            ])
            if !accessFields.isEmpty {
                PrintSection(title: "Access") {
                    ReportFieldList(fields: accessFields)
                }
            }

            if !data.inviters.isEmpty {
                PrintSection(title: "Inviters") {
                    ReportFieldList(fields: reportFields(data.inviters.map {
                        (
                            $0.displayName,
                            [$0.email, $0.role].compactMap(\.self).filter { !$0.isEmpty }.joined(separator: " — ")
                        )
                    }))
                }
            }

            if let sections = test.sections, !sections.isEmpty {
                PrintSection(title: "Sections") {
                    ReportFieldList(fields: reportFields(sections.map {
                        ($0.displayName, $0.questionCount.map { "\($0) question\($0 == 1 ? "" : "s")" })
                    }))
                }
            }

            if let tags = test.tags, !tags.isEmpty {
                PrintSection(title: "Tags") { Text(tags.joined(separator: ", ")) }
            }

            if let instructions = test.instructions, !instructions.isEmpty {
                PrintSection(title: "Instructions") { HTMLText(html: instructions) }
            }
        }
    }
}

// MARK: - Interview report

/// A printable interview report: lifecycle, notes, and feedback.
struct InterviewReport: View {
    let data: InterviewReportData

    var body: some View {
        let interview = data.interview
        ReportDocument(
            title: data.title,
            subtitle: "HackerRank Interview Report"
        ) {
            PrintSection(title: "Interview") {
                ReportFieldList(fields: reportFields([
                    ("Title", data.title),
                    ("Status", DisplayFormat.enumLabel(interview.status)),
                    ("Scheduled start", DisplayFormat.date(data.detail?.scheduledFrom)),
                    ("Scheduled end", DisplayFormat.date(data.detail?.scheduledTo)),
                    ("Created", DisplayFormat.date(interview.createdAt)),
                    ("Updated", DisplayFormat.date(interview.updatedAt)),
                    ("Ended", DisplayFormat.date(interview.endedAt)),
                    ("Thumbs up", interview.thumbsUp.map(String.init)),
                    ("Report URL", interview.reportURL),
                    ("Result URL", data.detail?.resultURL),
                    ("Résumé URL", data.detail?.resumeURL)
                ]))
            }

            let people = reportFields([
                ("Candidate", data.detail?.candidate?.displayName),
                ("Created by", data.detail?.user?.displayName)
            ] + (data.detail?.interviewers ?? []).map { ("Interviewer", $0.displayName) })
            if !people.isEmpty {
                PrintSection(title: "People") {
                    ReportFieldList(fields: people)
                }
            }

            if !data.notes.isEmpty {
                PrintSection(title: "Notes") { Text(data.notes) }
            }

            if let feedback = interview.feedback, !feedback.isEmpty {
                PrintSection(title: "Feedback") { Text(feedback) }
            }

            if let transcript = data.transcriptText {
                PrintSection(title: "Transcript") { Text(transcript) }
            }
        }
    }
}

// MARK: - Question report

/// A printable question report: configuration, skills, tags, and problem statement.
struct QuestionReport: View {
    let data: QuestionReportData

    var body: some View {
        let question = data.question
        ReportDocument(title: question.name, subtitle: "HackerRank Question Report") {
            PrintSection(title: "Question") {
                ReportFieldList(fields: reportFields([
                    ("Type", DisplayFormat.enumLabel(question.type)),
                    ("Unique ID", question.uniqueID),
                    ("Status", DisplayFormat.enumLabel(question.status)),
                    ("Max score", question.maxScore.map { $0.formatted() }),
                    ("Recommended duration", question.recommendedDuration.map { "\($0) minutes" }),
                    ("Created", DisplayFormat.date(question.createdAt)),
                    ("Languages", DisplayFormat.languages(question.languages)),
                    ("Skills", DisplayFormat.list(question.skills))
                ]))
            }

            if let tags = question.tags, !tags.isEmpty {
                PrintSection(title: "Tags") { Text(tags.joined(separator: ", ")) }
            }

            if !data.options.isEmpty {
                PrintSection(title: "Options") {
                    ReportFieldList(fields: reportFields(data.options.indices.map {
                        ("Option \($0 + 1)", data.optionLabel(at: $0))
                    }))
                }
            }

            if let answer = data.correctAnswer, !answer.isEmpty {
                PrintSection(title: "Correct answer") { Text(answer) }
            }

            if let statement = question.problemStatement, !statement.isEmpty {
                PrintSection(title: "Problem statement") { HTMLText(html: statement) }
            }

            if let notes = data.internalNotes, !notes.isEmpty {
                PrintSection(title: "Internal notes") { HTMLText(html: notes) }
            }
        }
    }
}

#Preview("Candidate report") {
    let json = #"""
    {"id":"c1","email":"ada@example.com","full_name":"Ada Lovelace","score":92.0,
     "percentage_score":92.0,"integrity_status":"clean","plagiarism_status":false,
     "status":7,"ats_state":2,"attempt_starttime":"2026-05-02T10:00:00Z",
     "attempt_endtime":"2026-05-02T11:15:00Z","tags":["shortlist"],
     "feedback":"Excellent problem decomposition."}
    """#
    let candidate = try? JSONDecoder().decode(TestCandidate.self, from: Data(json.utf8))
    return ScrollView {
        if let candidate { CandidateReport(candidate: candidate) }
    }
    .frame(width: 540, height: 600)
}
