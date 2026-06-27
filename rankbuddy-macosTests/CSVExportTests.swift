import Foundation
@testable import rankbuddy_macos
import Testing

/// Coverage for CSV export (#39): RFC-4180 field escaping and the per-collection documents.
struct CSVExportTests {
    @Test func `fields are only quoted when they contain a comma, quote, or newline`() {
        #expect(CSVExport.field("plain") == "plain")
        #expect(CSVExport.field("a,b") == "\"a,b\"")
        #expect(CSVExport.field("line\nbreak") == "\"line\nbreak\"")
        // Embedded quotes are doubled.
        #expect(CSVExport.field("say \"hi\"") == "\"say \"\"hi\"\"\"")
    }

    @Test func `a document is a header row over escaped data rows`() {
        let csv = CSVExport.document(header: ["A", "B"], rows: [["1", "x,y"], ["2", "z"]])
        #expect(csv == "A,B\n1,\"x,y\"\n2,z")
    }

    @Test func `the candidates document has a header and one row per candidate`() throws {
        let json = #"""
        [{"id":"c1","email":"ada@example.com","full_name":"Ada, Lovelace","score":92.0,
          "status":7,"plagiarism_status":false},
         {"id":"c2","email":"alan@example.com"}]
        """#
        let candidates = try JSONDecoder().decode([TestCandidate].self, from: Data(json.utf8))
        let csv = CSVExport.candidates(candidates)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3) // header + 2
        #expect(lines[0].hasPrefix("Name,Email,Score"))
        // The comma in the name forces quoting.
        #expect(lines[1].contains("\"Ada, Lovelace\""))
        #expect(lines[1].contains("ada@example.com"))
    }
}
