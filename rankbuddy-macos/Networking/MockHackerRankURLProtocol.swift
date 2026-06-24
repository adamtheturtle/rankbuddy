import Foundation

/// A `URLProtocol` that serves deterministic, sanitized demo data for the HackerRank
/// endpoints (#10). Installed only on `URLSession.rankBuddyDemo`, so it never intercepts
/// real traffic. It lets the app run in a demo mode — populated lists and detail views
/// without a real token — which also powers the website screenshots (#28) and manual
/// verification.
///
/// `nonisolated` because the URL loading system calls these methods on its own threads,
/// not the main actor.
final nonisolated class MockHackerRankURLProtocol: URLProtocol {
    /// Which demo data the mock serves, selected by `RANKBUDDY_DEMO_SCENARIO` so the
    /// app's empty/error states can be exercised without a live token (#10).
    enum Scenario: String {
        /// Populated lists, including a multi-page tests collection.
        case success
        /// Every collection is empty, to show the empty states.
        case empty
        /// A `401`, to show the authentication-failure state.
        case unauthorized
        /// A `200` with invalid JSON, to show the decode-failure state.
        case malformed

        /// The scenario selected by the environment, defaulting to `.success`.
        static var current: Self {
            let raw = ProcessInfo.processInfo.environment["RANKBUDDY_DEMO_SCENARIO"] ?? ""
            return Self(rawValue: raw) ?? .success
        }
    }

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }

        switch Scenario.current {
        case .success:
            respond(url: url, statusCode: 200, body: Self.body(for: url))
        case .empty:
            respond(url: url, statusCode: 200, body: #"{"data":[],"next":null}"#)
        case .unauthorized:
            respond(url: url, statusCode: 401, body: #"{"error":"Invalid or expired token"}"#)
        case .malformed:
            respond(url: url, statusCode: 200, body: "{ not valid json ")
        }
    }

    override func stopLoading() {}

    /// Sends a single complete response with the given status and JSON body.
    private func respond(url: URL, statusCode: Int, body: String) {
        guard let client else { return }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ) else {
            client.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: Data(body.utf8))
        client.urlProtocolDidFinishLoading(self)
    }

    /// Picks the fixture for a request path. Candidates are checked first because their
    /// path also contains `/tests/`. The tests collection is paginated to exercise the
    /// client's `next`-following path.
    private static func body(for url: URL) -> String {
        let path = url.path
        if path.contains("/candidates") {
            return candidatesJSON
        }
        if path.contains("/questions") {
            return questionsJSON
        }
        if path.contains("/interviews") {
            return interviewsJSON
        }
        if path.contains("/tests") {
            let isSecondPage = url.query?.contains("offset=3") ?? false
            return isSecondPage ? testsPage2JSON : testsPage1JSON
        }
        return #"{"data":[],"next":null}"#
    }

    // MARK: - Fixtures (deterministic demo data; no real personal data)

    private static let testsPage1JSON = #"""
    {"data":[
      {"id":"t1","unique_id":"backend-screen","name":"Backend Engineer Screen","state":"active",
       "starttime":"2026-05-01T09:00:00Z","endtime":"2026-06-01T09:00:00Z","duration":90,
       "languages":["python","go","java"],"cutoff_score":70,"tags":["backend","screening"],
       "enable_proctoring":true,"instructions":"Solve all questions within the time limit.","questions":["q1","q2"]},
      {"id":"t2","unique_id":"frontend-takehome","name":"Frontend Take-Home","state":"active",
       "starttime":"2026-05-10T09:00:00Z","duration":120,"languages":["javascript","typescript"],
       "cutoff_score":65,"tags":["frontend"]},
      {"id":"t3","unique_id":"ds-quiz","name":"Data Structures Quiz","state":"archived",
       "duration":45,"languages":["cpp"],"cutoff_score":80,"tags":["algorithms","mcq"]}
    ],"next":"https://www.hackerrank.com/x/api/v3/tests?limit=3&offset=3"}
    """#

    private static let testsPage2JSON = #"""
    {"data":[
      {"id":"t4","unique_id":"sre-screen","name":"SRE On-Call Screen","state":"active",
       "starttime":"2026-05-15T09:00:00Z","duration":75,"languages":["python","bash"],
       "cutoff_score":72,"tags":["sre","backend"],"draft":true},
      {"id":"t5","unique_id":"ml-fundamentals","name":"ML Fundamentals","state":"active",
       "duration":60,"languages":["python"],"cutoff_score":68,"tags":["ml"],"locked":true}
    ],"next":null}
    """#

    private static let candidatesJSON = #"""
    {"data":[
      {"id":"c1","email":"ada@example.com","full_name":"Ada Lovelace","score":92.0,
       "percentage_score":92.0,"integrity_status":"clean","plagiarism_status":false,
       "attempt_starttime":"2026-05-02T10:00:00Z","attempt_endtime":"2026-05-02T11:15:00Z",
       "tags":["shortlist"],"feedback":"Excellent problem decomposition."},
      {"id":"c2","email":"alan@example.com","full_name":"Alan Turing","score":81.5,
       "percentage_score":81.5,"integrity_status":"clean","plagiarism_status":false,
       "attempt_starttime":"2026-05-03T14:00:00Z","attempt_endtime":"2026-05-03T15:10:00Z"},
      {"id":"c3","email":"grace@example.com","full_name":"Grace Hopper","score":58.0,
       "percentage_score":58.0,"integrity_status":"review","plagiarism_status":true,
       "attempt_starttime":"2026-05-04T08:30:00Z"}
    ],"next":null}
    """#

    private static let questionsJSON = #"""
    {"data":[
      {"id":"q1","unique_id":"two-sum","type":"code","name":"Two Sum","status":"published",
       "languages":["python","go","java"],"max_score":100.0,"recommended_duration":20,
       "tags":["arrays","hashing"],"problem_statement":"Return indices of two numbers adding to a target."},
      {"id":"q2","unique_id":"lru-cache","type":"code","name":"LRU Cache","status":"published",
       "languages":["python","cpp"],"max_score":150.0,"recommended_duration":35,"tags":["design"]},
      {"id":"q3","unique_id":"sql-joins","type":"mcq","name":"SQL Joins","status":"published",
       "max_score":50.0,"recommended_duration":10,"tags":["sql"]}
    ],"next":null}
    """#

    private static let interviewsJSON = #"""
    {"data":[
      {"id":"i1","status":"completed","url":"https://www.hackerrank.com/x/interviews/i1",
       "title":"Senior Backend — Pairing","created_at":"2026-05-05T13:00:00Z",
       "ended_at":"2026-05-05T14:00:00Z","thumbs_up":1,"feedback":"Strong system design."},
      {"id":"i2","status":"scheduled","url":"https://www.hackerrank.com/x/interviews/i2",
       "title":"Frontend — Live Coding","created_at":"2026-05-12T16:00:00Z"}
    ],"next":null}
    """#
}

extension URLSession {
    /// A session whose only protocol is the demo mock, so demo requests are served from
    /// the bundled fixtures and never hit the network.
    static let rankBuddyDemo: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockHackerRankURLProtocol.self]
        return URLSession(configuration: configuration)
    }()
}
