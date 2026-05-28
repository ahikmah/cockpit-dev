import XCTest
import NIOHTTP1
@testable import CockpitDev

final class OpenSpecPMAPIClientTests: CockpitDevTestCase {
    private var server: MockHTTPServer!
    private var client: OpenSpecPMAPIClient!

    override func setUp() async throws {
        try await super.setUp()
        server = MockHTTPServer()
        let port = try await server.start()
        client = OpenSpecPMAPIClient(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            tokenProvider: { "gitlab-oauth-token" }
        )
    }

    override func tearDown() async throws {
        try await server.stop()
        server = nil
        client = nil
        try await super.tearDown()
    }

    func testFetchFeaturesUsesGitLabTokenToReadDatabaseMetadata() async throws {
        var capturedHead: HTTPRequestHead?
        server.handler = { head, _ in
            capturedHead = head
            let features = """
            [{"id":"feature-15","externalIssueId":85,"title":"CYINT84-015: UI/UX Reskin","status":"COMPLETED","priority":"CRITICAL","startDate":"2026-04-10T00:00:00.000Z","dueDate":"2026-04-15T00:00:00.000Z","storyPoints":25,"milestone":"Phase 1","branchName":null,"dependencies":["feature-5"],"assignee":null}]
            """
            return (200, [], features.data(using: .utf8)!)
        }

        let features = try await client.fetchFeatures(
            repositoryURL: "https://gitlab.orbit-poc.com/devbuddy/cyint.git"
        )

        XCTAssertTrue(capturedHead?.uri.contains("/api/native/features?") == true)
        XCTAssertTrue(capturedHead?.uri.contains("repoUrl=") == true)
        XCTAssertEqual(capturedHead?.headers["Authorization"].first, "Bearer gitlab-oauth-token")
        XCTAssertEqual(features.first?.externalIssueId, 85)
        XCTAssertEqual(features.first?.storyPoints, 25)
        XCTAssertEqual(features.first?.priority, .critical)
        XCTAssertEqual(features.first?.status, .completed)
        XCTAssertEqual(features.first?.dependencyReferences, ["feature-5"])
    }
}
