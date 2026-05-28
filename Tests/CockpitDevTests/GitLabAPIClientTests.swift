import XCTest
import Foundation
import NIO
import NIOHTTP1
@testable import CockpitDev

// MARK: - Mock HTTP Server

/// A lightweight mock HTTP server for testing GitLab API client interactions.
final class MockHTTPServer: @unchecked Sendable {
    private let group: EventLoopGroup
    private var channel: Channel?
    let port: Int

    /// Handler closure that receives the request and returns (statusCode, headers, body).
    var handler: ((HTTPRequestHead, Data?) -> (Int, [(String, String)], Data))?

    init(port: Int = 0) {
        self.port = port
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    func start() async throws -> Int {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(MockHTTPHandler(server: self))
                }
            }

        let channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
        self.channel = channel
        return channel.localAddress!.port!
    }

    func stop() async throws {
        try await channel?.close()
        try await group.shutdownGracefully()
    }
}

// MARK: - Mock HTTP Handler

final class MockHTTPHandler: ChannelInboundHandler {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let server: MockHTTPServer
    private var requestHead: HTTPRequestHead?
    private var requestBody: Data = Data()

    init(server: MockHTTPServer) {
        self.server = server
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            requestHead = head
            requestBody = Data()
        case .body(var buffer):
            if let bytes = buffer.readBytes(length: buffer.readableBytes) {
                requestBody.append(contentsOf: bytes)
            }
        case .end:
            guard let head = requestHead else { return }

            let (statusCode, headers, body) = server.handler?(head, requestBody.isEmpty ? nil : requestBody)
                ?? (200, [], Data())

            var responseHeaders = HTTPHeaders()
            responseHeaders.add(name: "Content-Type", value: "application/json")
            responseHeaders.add(name: "Content-Length", value: "\(body.count)")
            for (name, value) in headers {
                responseHeaders.add(name: name, value: value)
            }

            let responseHead = HTTPResponseHead(
                version: head.version,
                status: HTTPResponseStatus(statusCode: statusCode),
                headers: responseHeaders
            )

            context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
            var buffer = context.channel.allocator.buffer(capacity: body.count)
            buffer.writeBytes(body)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}


// MARK: - GitLabAPIClient Tests

final class GitLabAPIClientTests: CockpitDevTestCase {
    var server: MockHTTPServer!
    var client: GitLabAPIClient!
    var serverPort: Int!

    override func setUp() async throws {
        try await super.setUp()
        server = MockHTTPServer()
        serverPort = try await server.start()
        let baseURL = URL(string: "http://127.0.0.1:\(serverPort!)")!
        client = GitLabAPIClient(
            baseURL: baseURL,
            tokenProvider: { "test-token" }
        )
    }

    override func tearDown() async throws {
        try await server.stop()
        server = nil
        client = nil
        try await super.tearDown()
    }

    // MARK: - Authentication Tests

    func testRequestIncludesAuthorizationHeader() async throws {
        var capturedHeaders: HTTPHeaders?

        server.handler = { head, _ in
            capturedHeaders = head.headers
            let user = """
            {"id":1,"username":"testuser","name":"Test User","avatar_url":null,"email":"test@example.com","state":"active","web_url":"https://gitlab.com/testuser"}
            """
            return (200, [], user.data(using: .utf8)!)
        }

        _ = try await client.getCurrentUser()

        XCTAssertEqual(capturedHeaders?["Authorization"].first, "Bearer test-token")
    }

    func testRequestIncludesContentTypeHeader() async throws {
        var capturedHeaders: HTTPHeaders?

        server.handler = { head, _ in
            capturedHeaders = head.headers
            let user = """
            {"id":1,"username":"testuser","name":"Test User","avatar_url":null,"email":"test@example.com","state":"active","web_url":"https://gitlab.com/testuser"}
            """
            return (200, [], user.data(using: .utf8)!)
        }

        _ = try await client.getCurrentUser()

        XCTAssertEqual(capturedHeaders?["Content-Type"].first, "application/json")
    }

    // MARK: - Issue Tests

    func testCreateIssue() async throws {
        var capturedBody: [String: Any]?

        server.handler = { head, body in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/issues"))
            XCTAssertEqual(head.method, .POST)
            if let body {
                capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }

            let issue = """
            {"id":100,"iid":1,"project_id":1,"title":"Test Issue","description":"A test","state":"opened","labels":["bug"],"weight":3,"assignee":null,"assignees":[],"milestone":null,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-01T00:00:00Z","closed_at":null,"start_date":"2024-01-02","due_date":"2024-01-10","web_url":"https://gitlab.com/test/project/-/issues/1"}
            """
            return (201, [], issue.data(using: .utf8)!)
        }

        let issue = try await client.createIssue(
            projectId: 1,
            title: "Test Issue",
            description: "A test",
            labels: ["bug"],
            weight: 3,
            assigneeId: 7,
            startDate: "2024-01-02",
            dueDate: "2024-01-10",
            milestoneId: 12
        )

        XCTAssertEqual(capturedBody?["assignee_ids"] as? [Int], [7])
        XCTAssertEqual(capturedBody?["start_date"] as? String, "2024-01-02")
        XCTAssertEqual(capturedBody?["due_date"] as? String, "2024-01-10")
        XCTAssertEqual(capturedBody?["milestone_id"] as? Int, 12)
        XCTAssertEqual(issue.id, 100)
        XCTAssertEqual(issue.iid, 1)
        XCTAssertEqual(issue.title, "Test Issue")
        XCTAssertEqual(issue.state, "opened")
        XCTAssertEqual(issue.labels, ["bug"])
        XCTAssertEqual(issue.weight, 3)
        XCTAssertEqual(issue.startDate, "2024-01-02")
        XCTAssertEqual(issue.dueDate, "2024-01-10")
    }

    func testUpdateIssue() async throws {
        var capturedBody: [String: Any]?

        server.handler = { head, body in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/issues/5"))
            XCTAssertEqual(head.method, .PUT)
            if let body {
                capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }

            let issue = """
            {"id":100,"iid":5,"project_id":1,"title":"Updated Title","description":null,"state":"opened","labels":["feature"],"weight":5,"assignee":null,"assignees":[],"milestone":null,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-02T00:00:00Z","closed_at":null,"start_date":"2024-01-03","due_date":"2024-01-11","web_url":"https://gitlab.com/test/project/-/issues/5"}
            """
            return (200, [], issue.data(using: .utf8)!)
        }

        let fields = IssueUpdateFields(
            title: "Updated Title",
            labels: ["feature"],
            weight: 5,
            assigneeIds: [9],
            startDate: "2024-01-03",
            dueDate: "2024-01-11",
            milestoneId: 22
        )
        let issue = try await client.updateIssue(projectId: 1, issueIid: 5, fields: fields)

        XCTAssertEqual(capturedBody?["assignee_ids"] as? [Int], [9])
        XCTAssertEqual(capturedBody?["start_date"] as? String, "2024-01-03")
        XCTAssertEqual(capturedBody?["due_date"] as? String, "2024-01-11")
        XCTAssertEqual(capturedBody?["milestone_id"] as? Int, 22)
        XCTAssertEqual(issue.title, "Updated Title")
        XCTAssertEqual(issue.labels, ["feature"])
        XCTAssertEqual(issue.weight, 5)
        XCTAssertEqual(issue.startDate, "2024-01-03")
    }

    func testUpdateIssueCanClearMilestone() async throws {
        var capturedBody: [String: Any]?

        server.handler = { _, body in
            if let body {
                capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }
            let issue = """
            {"id":100,"iid":5,"project_id":1,"title":"Updated Title","description":null,"state":"opened","labels":[],"weight":null,"assignee":null,"assignees":[],"milestone":null,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-02T00:00:00Z","closed_at":null,"due_date":null,"web_url":"https://gitlab.com/test/project/-/issues/5"}
            """
            return (200, [], issue.data(using: .utf8)!)
        }

        var fields = IssueUpdateFields()
        fields.clearMilestone = true
        _ = try await client.updateIssue(projectId: 1, issueIid: 5, fields: fields)

        XCTAssertTrue(capturedBody?["milestone_id"] is NSNull)
    }

    func testCloseIssue() async throws {
        server.handler = { head, body in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/issues/3"))
            XCTAssertEqual(head.method, .PUT)

            // Verify state_event is "close"
            if let body = body,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                XCTAssertEqual(json["state_event"] as? String, "close")
            }

            let issue = """
            {"id":100,"iid":3,"project_id":1,"title":"Closed Issue","description":null,"state":"closed","labels":[],"weight":null,"assignee":null,"assignees":[],"milestone":null,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-02T00:00:00Z","closed_at":"2024-01-02T00:00:00Z","due_date":null,"web_url":"https://gitlab.com/test/project/-/issues/3"}
            """
            return (200, [], issue.data(using: .utf8)!)
        }

        try await client.closeIssue(projectId: 1, issueIid: 3)
    }

    func testFetchIssues() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/issues"))
            XCTAssertEqual(head.method, .GET)
            XCTAssertTrue(head.uri.contains("state=all"), "Issue sync must include closed/completed GitLab issues.")

            let issues = """
            [{"id":1,"iid":1,"project_id":1,"title":"Issue 1","description":null,"state":"opened","labels":[],"weight":null,"assignee":null,"assignees":[],"milestone":null,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-01T00:00:00Z","closed_at":null,"due_date":null,"web_url":"https://gitlab.com/test/project/-/issues/1"},{"id":2,"iid":2,"project_id":1,"title":"Issue 2","description":null,"state":"opened","labels":[],"weight":null,"assignee":null,"assignees":[],"milestone":null,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-01T00:00:00Z","closed_at":null,"due_date":null,"web_url":"https://gitlab.com/test/project/-/issues/2"}]
            """
            return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], issues.data(using: .utf8)!)
        }

        let issues = try await client.fetchIssues(projectId: 1)

        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues[0].title, "Issue 1")
        XCTAssertEqual(issues[1].title, "Issue 2")
    }

    func testFetchIssuesDecodesStartDate() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/issues"))
            let issues = """
            [{"id":1,"iid":1,"project_id":1,"title":"Scheduled","description":null,"state":"opened","labels":[],"weight":8,"assignee":null,"assignees":[],"milestone":null,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-01T00:00:00Z","closed_at":null,"start_date":"2024-02-03","due_date":"2024-02-09","web_url":"https://gitlab.com/test/project/-/issues/1"}]
            """
            return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], issues.data(using: .utf8)!)
        }

        let issues = try await client.fetchIssues(projectId: 1)

        XCTAssertEqual(issues.first?.startDate, "2024-02-03")
        XCTAssertEqual(issues.first?.dueDate, "2024-02-09")
    }


    // MARK: - Merge Request Tests

    func testFetchMergeRequests() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/merge_requests"))
            XCTAssertTrue(head.uri.contains("state=opened"))

            let mrs = """
            [{"id":10,"iid":1,"project_id":1,"title":"MR 1","description":null,"state":"opened","source_branch":"feature","target_branch":"main","author":{"id":1,"username":"dev","name":"Developer","avatar_url":null,"email":null,"state":"active","web_url":null},"assignee":null,"pipeline":null,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-01T00:00:00Z","merged_at":null,"closed_at":null,"web_url":"https://gitlab.com/test/project/-/merge_requests/1"}]
            """
            return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], mrs.data(using: .utf8)!)
        }

        let mrs = try await client.fetchMergeRequests(projectId: 1, state: "opened")

        XCTAssertEqual(mrs.count, 1)
        XCTAssertEqual(mrs[0].title, "MR 1")
        XCTAssertEqual(mrs[0].sourceBranch, "feature")
        XCTAssertEqual(mrs[0].targetBranch, "main")
    }

    func testFetchMRDiff() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/merge_requests/1/changes"))

            let response = """
            {"changes":[{"old_path":"file.swift","new_path":"file.swift","a_mode":"100644","b_mode":"100644","diff":"@@ -1,3 +1,4 @@\\n line1\\n+line2\\n line3","new_file":false,"renamed_file":false,"deleted_file":false}]}
            """
            return (200, [], response.data(using: .utf8)!)
        }

        let diffs = try await client.fetchMRDiff(projectId: 1, mrIid: 1)

        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].oldPath, "file.swift")
        XCTAssertFalse(diffs[0].newFile)
    }

    func testFetchMRCommits() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/merge_requests/7/commits"))
            XCTAssertEqual(head.method, .GET)

            let commits = """
            [{"id":"abc123","short_id":"abc123","title":"CYINT84-015 finish work","message":"CYINT84-015 finish work","author_name":"Dev","author_email":"dev@example.com","committer_name":"Dev","committer_email":"dev@example.com","created_at":"2026-04-15T10:00:00Z","committed_date":"2026-04-15T12:00:00Z"}]
            """
            return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], commits.data(using: .utf8)!)
        }

        let commits = try await client.fetchMRCommits(projectId: 1, mrIid: 7)

        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commits.first?.shortId, "abc123")
        XCTAssertEqual(commits.first?.committedDate, ISO8601DateFormatter().date(from: "2026-04-15T12:00:00Z"))
    }

    func testFetchIssueRelatedMergeRequests() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/issues/68/related_merge_requests"))
            XCTAssertEqual(head.method, .GET)

            let mrs = """
            [{"id":25,"iid":25,"project_id":1,"title":"Implementation cleanup","description":null,"state":"merged","source_branch":"feature/refactor","target_branch":"main","author":{"id":1,"username":"dev","name":"Developer","avatar_url":null,"email":null,"state":"active","web_url":null},"assignee":null,"pipeline":null,"created_at":"2026-04-12T00:00:00Z","updated_at":"2026-04-16T00:00:00Z","merged_at":"2026-04-16T00:00:00Z","closed_at":null,"web_url":"https://gitlab.example.com/test/project/-/merge_requests/25"}]
            """
            return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], mrs.data(using: .utf8)!)
        }

        let mrs = try await client.fetchIssueRelatedMergeRequests(projectId: 1, issueIid: 68)

        XCTAssertEqual(mrs.map(\.iid), [25])
    }

    func testFetchIssueNotes() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/issues/68/notes"))
            XCTAssertEqual(head.method, .GET)

            let notes = """
            [{"id":1,"body":"mentioned in merge request !25","author":{"id":1,"username":"dev","name":"Developer","avatar_url":null,"email":null,"state":"active","web_url":null},"created_at":"2026-04-16T11:35:32Z","updated_at":"2026-04-16T11:35:32Z","system":true,"resolvable":false,"resolved":null,"resolved_by":null,"position":null}]
            """
            return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], notes.data(using: .utf8)!)
        }

        let notes = try await client.fetchIssueNotes(projectId: 1, issueIid: 68)

        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.body, "mentioned in merge request !25")
        XCTAssertEqual(notes.first?.createdAt, ISO8601DateFormatter().date(from: "2026-04-16T11:35:32Z"))
    }

    func testFetchMRDiscussions() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/merge_requests/1/discussions"))

            let discussions = """
            [{"id":"abc123","individual_note":false,"notes":[{"id":1,"body":"Looks good!","author":{"id":1,"username":"reviewer","name":"Reviewer","avatar_url":null,"email":null,"state":"active","web_url":null},"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-01T00:00:00Z","system":false,"resolvable":true,"resolved":false,"resolved_by":null,"position":null}]}]
            """
            return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], discussions.data(using: .utf8)!)
        }

        let discussions = try await client.fetchMRDiscussions(projectId: 1, mrIid: 1)

        XCTAssertEqual(discussions.count, 1)
        XCTAssertEqual(discussions[0].id, "abc123")
        XCTAssertEqual(discussions[0].notes.count, 1)
        XCTAssertEqual(discussions[0].notes[0].body, "Looks good!")
    }

    func testCreateMRNote() async throws {
        var capturedBody: [String: Any]?

        server.handler = { head, body in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/merge_requests/1/discussions"))
            XCTAssertEqual(head.method, .POST)

            if let body = body {
                capturedBody = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            }

            let response = """
            {"id":"disc123"}
            """
            return (201, [], response.data(using: .utf8)!)
        }

        try await client.createMRNote(projectId: 1, mrIid: 1, body: "Nice work!")

        XCTAssertEqual(capturedBody?["body"] as? String, "Nice work!")
    }

    func testApproveMR() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/merge_requests/1/approve"))
            XCTAssertEqual(head.method, .POST)
            return (200, [], "{}".data(using: .utf8)!)
        }

        try await client.approveMR(projectId: 1, mrIid: 1)
    }

    func testMergeMR() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/merge_requests/1/merge"))
            XCTAssertEqual(head.method, .PUT)

            let mr = """
            {"id":10,"iid":1,"project_id":1,"title":"MR 1","description":null,"state":"merged","source_branch":"feature","target_branch":"main","author":{"id":1,"username":"dev","name":"Developer","avatar_url":null,"email":null,"state":"active","web_url":null},"assignee":null,"pipeline":null,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-02T00:00:00Z","merged_at":"2024-01-02T00:00:00Z","closed_at":null,"web_url":"https://gitlab.com/test/project/-/merge_requests/1"}
            """
            return (200, [], mr.data(using: .utf8)!)
        }

        let mr = try await client.mergeMR(projectId: 1, mrIid: 1)

        XCTAssertEqual(mr.state, "merged")
    }

    // MARK: - User Tests

    func testSearchUsers() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/users"))
            XCTAssertTrue(head.uri.contains("search=john"))

            let users = """
            [{"id":1,"username":"john","name":"John Doe","avatar_url":null,"email":"john@example.com","state":"active","web_url":"https://gitlab.com/john"}]
            """
            return (200, [], users.data(using: .utf8)!)
        }

        let users = try await client.searchUsers(query: "john")

        XCTAssertEqual(users.count, 1)
        XCTAssertEqual(users[0].username, "john")
        XCTAssertEqual(users[0].name, "John Doe")
    }

    func testGetCurrentUser() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/user"))
            XCTAssertEqual(head.method, .GET)

            let user = """
            {"id":42,"username":"currentuser","name":"Current User","avatar_url":"https://example.com/avatar.png","email":"current@example.com","state":"active","web_url":"https://gitlab.com/currentuser"}
            """
            return (200, [], user.data(using: .utf8)!)
        }

        let user = try await client.getCurrentUser()

        XCTAssertEqual(user.id, 42)
        XCTAssertEqual(user.username, "currentuser")
        XCTAssertEqual(user.email, "current@example.com")
    }


    // MARK: - Project Validation Tests

    func testValidateProjectAccess() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/"))
            XCTAssertEqual(head.method, .GET)

            let project = """
            {"id":123,"name":"my-project","name_with_namespace":"My Org / my-project","path":"my-project","path_with_namespace":"myorg/my-project","default_branch":"main","http_url_to_repo":"https://gitlab.com/myorg/my-project.git","ssh_url_to_repo":"git@gitlab.com:myorg/my-project.git","web_url":"https://gitlab.com/myorg/my-project","visibility":"private"}
            """
            return (200, [], project.data(using: .utf8)!)
        }

        let project = try await client.validateProjectAccess(url: "https://gitlab.com/myorg/my-project.git")

        XCTAssertEqual(project.id, 123)
        XCTAssertEqual(project.name, "my-project")
        XCTAssertEqual(project.pathWithNamespace, "myorg/my-project")
    }

    func testValidateProjectAccessWithSSHUrl() async throws {
        server.handler = { head, _ in
            let project = """
            {"id":456,"name":"backend","name_with_namespace":"Team / backend","path":"backend","path_with_namespace":"team/backend","default_branch":"develop","http_url_to_repo":"https://gitlab.com/team/backend.git","ssh_url_to_repo":"git@gitlab.com:team/backend.git","web_url":"https://gitlab.com/team/backend","visibility":"internal"}
            """
            return (200, [], project.data(using: .utf8)!)
        }

        let project = try await client.validateProjectAccess(url: "git@gitlab.com:team/backend.git")

        XCTAssertEqual(project.id, 456)
        XCTAssertEqual(project.pathWithNamespace, "team/backend")
    }

    // MARK: - Milestone Tests

    func testFetchMilestones() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/milestones"))
            XCTAssertEqual(head.method, .GET)

            let milestones = """
            [{"id":10,"iid":1,"project_id":1,"title":"Sprint 1","description":"First sprint","state":"active","start_date":"2024-01-01","due_date":"2024-01-14","created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-02T00:00:00Z","web_url":"https://gitlab.com/test/project/-/milestones/1"}]
            """
            return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], milestones.data(using: .utf8)!)
        }

        let milestones = try await client.fetchMilestones(projectId: 1)

        XCTAssertEqual(milestones.count, 1)
        XCTAssertEqual(milestones[0].id, 10)
        XCTAssertEqual(milestones[0].title, "Sprint 1")
        XCTAssertEqual(milestones[0].startDate, "2024-01-01")
        XCTAssertEqual(milestones[0].dueDate, "2024-01-14")
    }

    func testCreateMilestone() async throws {
        server.handler = { head, body in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/milestones"))
            XCTAssertEqual(head.method, .POST)

            if let body = body,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                XCTAssertEqual(json["title"] as? String, "Sprint 1")
                XCTAssertNotNil(json["start_date"])
                XCTAssertNotNil(json["due_date"])
            }

            let milestone = """
            {"id":10,"iid":1,"project_id":1,"title":"Sprint 1","description":null,"state":"active","start_date":"2024-01-01","due_date":"2024-01-14","created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-01T00:00:00Z","web_url":"https://gitlab.com/test/project/-/milestones/1"}
            """
            return (201, [], milestone.data(using: .utf8)!)
        }

        let startDate = ISO8601DateFormatter().date(from: "2024-01-01T00:00:00Z")!
        let dueDate = ISO8601DateFormatter().date(from: "2024-01-14T00:00:00Z")!

        let milestone = try await client.createMilestone(
            projectId: 1,
            title: "Sprint 1",
            startDate: startDate,
            dueDate: dueDate
        )

        XCTAssertEqual(milestone.title, "Sprint 1")
        XCTAssertEqual(milestone.state, "active")
    }

    func testDeleteMilestone() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/milestones/10"))
            XCTAssertEqual(head.method, .DELETE)
            return (204, [], Data())
        }

        try await client.deleteMilestone(projectId: 1, milestoneId: 10)
    }

    // MARK: - Repository File Tests

    func testFetchFileContent() async throws {
        let originalContent = "Hello, World!\nThis is a test file."
        let base64Content = Data(originalContent.utf8).base64EncodedString()

        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/repository/files/"))
            XCTAssertTrue(head.uri.contains("ref=main"))

            let response = """
            {"content":"\(base64Content)","encoding":"base64"}
            """
            return (200, [], response.data(using: .utf8)!)
        }

        let content = try await client.fetchFileContent(projectId: 1, filePath: "README.md", ref: "main")

        XCTAssertEqual(content, originalContent)
    }

    func testFetchFileContent_encodesNestedFilePathAsSingleGitLabParameter() async throws {
        let base64Content = Data("# Tasks".utf8).base64EncodedString()

        server.handler = { head, _ in
            XCTAssertTrue(
                head.uri.contains("/repository/files/openspec%2Fchanges%2Ftask-1%2Ftasks.md"),
                "Nested GitLab file paths must be percent-encoded inside the path parameter: \(head.uri)"
            )
            let response = """
            {"content":"\(base64Content)","encoding":"base64"}
            """
            return (200, [], response.data(using: .utf8)!)
        }

        let content = try await client.fetchFileContent(
            projectId: 1,
            filePath: "openspec/changes/task-1/tasks.md",
            ref: "orbit-dev-84"
        )

        XCTAssertEqual(content, "# Tasks")
    }

    func testFetchBranches() async throws {
        server.handler = { head, _ in
            XCTAssertTrue(head.uri.contains("/api/v4/projects/1/repository/branches"))

            let branches = """
            [{"name":"main","merged":false,"protected":true,"developers_can_push":false,"developers_can_merge":false,"can_push":true,"default":true,"web_url":"https://gitlab.com/test/project/-/tree/main"},{"name":"develop","merged":false,"protected":false,"developers_can_push":true,"developers_can_merge":true,"can_push":true,"default":false,"web_url":"https://gitlab.com/test/project/-/tree/develop"}]
            """
            return (200, [("X-Total-Pages", "1"), ("X-Next-Page", "")], branches.data(using: .utf8)!)
        }

        let branches = try await client.fetchBranches(projectId: 1)

        XCTAssertEqual(branches.count, 2)
        XCTAssertEqual(branches[0].name, "main")
        XCTAssertTrue(branches[0].isDefault)
        XCTAssertEqual(branches[1].name, "develop")
        XCTAssertFalse(branches[1].isDefault)
    }

    // MARK: - Error Handling Tests

    func testUnauthorizedError() async throws {
        server.handler = { _, _ in
            return (401, [], "{\"message\":\"401 Unauthorized\"}".data(using: .utf8)!)
        }

        do {
            _ = try await client.getCurrentUser()
            XCTFail("Expected unauthorized error")
        } catch let error as GitLabAPIError {
            if case .unauthorized = error {
                // Expected
            } else {
                XCTFail("Expected unauthorized error, got: \(error)")
            }
        }
    }

    func testForbiddenError() async throws {
        server.handler = { _, _ in
            return (403, [], "{\"message\":\"403 Forbidden\"}".data(using: .utf8)!)
        }

        do {
            _ = try await client.getCurrentUser()
            XCTFail("Expected forbidden error")
        } catch let error as GitLabAPIError {
            if case .forbidden = error {
                // Expected
            } else {
                XCTFail("Expected forbidden error, got: \(error)")
            }
        }
    }

    func testNotFoundError() async throws {
        server.handler = { _, _ in
            return (404, [], "{\"message\":\"404 Project Not Found\"}".data(using: .utf8)!)
        }

        do {
            _ = try await client.validateProjectAccess(url: "https://gitlab.com/nonexistent/project.git")
            XCTFail("Expected not found error")
        } catch let error as GitLabAPIError {
            if case .notFound = error {
                // Expected
            } else {
                XCTFail("Expected not found error, got: \(error)")
            }
        }
    }

    func testRateLimitingWithRetryAfter() async throws {
        var requestCount = 0

        server.handler = { _, _ in
            requestCount += 1
            if requestCount == 1 {
                return (429, [("Retry-After", "1")], "{\"message\":\"Rate limit exceeded\"}".data(using: .utf8)!)
            }
            let user = """
            {"id":1,"username":"testuser","name":"Test User","avatar_url":null,"email":null,"state":"active","web_url":null}
            """
            return (200, [], user.data(using: .utf8)!)
        }

        let user = try await client.getCurrentUser()

        XCTAssertEqual(user.username, "testuser")
        XCTAssertEqual(requestCount, 2)
    }

    func testServerErrorRetry() async throws {
        var requestCount = 0

        server.handler = { _, _ in
            requestCount += 1
            if requestCount <= 2 {
                return (500, [], "{\"message\":\"Internal Server Error\"}".data(using: .utf8)!)
            }
            let user = """
            {"id":1,"username":"testuser","name":"Test User","avatar_url":null,"email":null,"state":"active","web_url":null}
            """
            return (200, [], user.data(using: .utf8)!)
        }

        let user = try await client.getCurrentUser()

        XCTAssertEqual(user.username, "testuser")
        XCTAssertEqual(requestCount, 3)
    }

    func testMaxRetriesExceeded() async throws {
        server.handler = { _, _ in
            return (500, [], "{\"message\":\"Internal Server Error\"}".data(using: .utf8)!)
        }

        do {
            _ = try await client.getCurrentUser()
            XCTFail("Expected max retries exceeded error")
        } catch let error as GitLabAPIError {
            switch error {
            case .maxRetriesExceeded:
                // Expected - retries exhausted wrapping the server error
                break
            case .serverError(let statusCode, _):
                XCTAssertEqual(statusCode, 500)
            default:
                XCTFail("Expected maxRetriesExceeded or serverError, got: \(error)")
            }
        }
    }

    // MARK: - Pagination Tests

    func testPaginationFetchesAllPages() async throws {
        server.handler = { head, _ in
            // Check if this is page 2
            if head.uri.contains("page=2") {
                let issues = """
                [{"id":2,"iid":2,"project_id":1,"title":"Issue 2","description":null,"state":"opened","labels":[],"weight":null,"assignee":null,"assignees":[],"milestone":null,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-01T00:00:00Z","closed_at":null,"due_date":null,"web_url":"https://gitlab.com/test/project/-/issues/2"}]
                """
                return (200, [("X-Total-Pages", "2"), ("X-Next-Page", "")], issues.data(using: .utf8)!)
            } else {
                // Page 1 (default)
                let issues = """
                [{"id":1,"iid":1,"project_id":1,"title":"Issue 1","description":null,"state":"opened","labels":[],"weight":null,"assignee":null,"assignees":[],"milestone":null,"created_at":"2024-01-01T00:00:00Z","updated_at":"2024-01-01T00:00:00Z","closed_at":null,"due_date":null,"web_url":"https://gitlab.com/test/project/-/issues/1"}]
                """
                return (200, [("X-Total-Pages", "2"), ("X-Next-Page", "2")], issues.data(using: .utf8)!)
            }
        }

        let issues = try await client.fetchIssues(projectId: 1)

        XCTAssertEqual(issues.count, 2)
        XCTAssertEqual(issues[0].title, "Issue 1")
        XCTAssertEqual(issues[1].title, "Issue 2")
    }
}
