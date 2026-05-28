import XCTest
@testable import CockpitDev

/// Integration tests for the WebhookServer.
final class WebhookServerTests: CockpitDevTestCase {

    // MARK: - Token Validation Tests

    func testValidateToken_withMatchingToken_returnsTrue() async {
        let server = WebhookServer(secretToken: "my-secret-token")
        let result = await server.validateToken("my-secret-token")
        XCTAssertTrue(result)
    }

    func testValidateToken_withMismatchedToken_returnsFalse() async {
        let server = WebhookServer(secretToken: "my-secret-token")
        let result = await server.validateToken("wrong-token")
        XCTAssertFalse(result)
    }

    func testValidateToken_withNilToken_returnsFalse() async {
        let server = WebhookServer(secretToken: "my-secret-token")
        let result = await server.validateToken(nil)
        XCTAssertFalse(result)
    }

    func testValidateToken_withNoSecretConfigured_acceptsAll() async {
        let server = WebhookServer(secretToken: nil)
        let result = await server.validateToken(nil)
        XCTAssertTrue(result)

        let result2 = await server.validateToken("any-token")
        XCTAssertTrue(result2)
    }

    func testValidateToken_withEmptySecret_acceptsAll() async {
        let server = WebhookServer(secretToken: "")
        let result = await server.validateToken(nil)
        XCTAssertTrue(result)
    }

    // MARK: - Issue Hook Parsing Tests

    func testParseEvent_issueHook_create() async throws {
        let server = WebhookServer()
        let payload = makeIssueHookPayload(action: "open")
        let event = try await server.parseEvent(eventHeader: "Issue Hook", body: payload)

        if case .issueHook(let issuePayload) = event {
            XCTAssertEqual(issuePayload.objectAttributes.action, "open")
            XCTAssertEqual(issuePayload.objectAttributes.id, 42)
            XCTAssertEqual(issuePayload.objectAttributes.iid, 7)
            XCTAssertEqual(issuePayload.objectAttributes.title, "Test Issue")
            XCTAssertEqual(issuePayload.objectAttributes.state, "opened")
            XCTAssertEqual(issuePayload.project.id, 100)
        } else {
            XCTFail("Expected issueHook event")
        }
    }

    func testParseEvent_issueHook_update() async throws {
        let server = WebhookServer()
        let payload = makeIssueHookPayload(action: "update")
        let event = try await server.parseEvent(eventHeader: "Issue Hook", body: payload)

        if case .issueHook(let issuePayload) = event {
            XCTAssertEqual(issuePayload.objectAttributes.action, "update")
        } else {
            XCTFail("Expected issueHook event")
        }
    }

    func testParseEvent_issueHook_close() async throws {
        let server = WebhookServer()
        let payload = makeIssueHookPayload(action: "close", state: "closed")
        let event = try await server.parseEvent(eventHeader: "Issue Hook", body: payload)

        if case .issueHook(let issuePayload) = event {
            XCTAssertEqual(issuePayload.objectAttributes.action, "close")
            XCTAssertEqual(issuePayload.objectAttributes.state, "closed")
        } else {
            XCTFail("Expected issueHook event")
        }
    }

    func testParseEvent_issueHook_destroy() async throws {
        let server = WebhookServer()
        let payload = makeIssueHookPayload(action: "destroy", state: "closed")
        let event = try await server.parseEvent(eventHeader: "Issue Hook", body: payload)

        if case .issueHook(let issuePayload) = event {
            XCTAssertEqual(issuePayload.objectAttributes.action, "destroy")
        } else {
            XCTFail("Expected issueHook event")
        }
    }

    // MARK: - Merge Request Hook Parsing Tests

    func testParseEvent_mergeRequestHook_open() async throws {
        let server = WebhookServer()
        let payload = makeMRHookPayload(action: "open", state: "opened")
        let event = try await server.parseEvent(eventHeader: "Merge Request Hook", body: payload)

        if case .mergeRequestHook(let mrPayload) = event {
            XCTAssertEqual(mrPayload.objectAttributes.action, "open")
            XCTAssertEqual(mrPayload.objectAttributes.state, "opened")
            XCTAssertEqual(mrPayload.objectAttributes.id, 99)
            XCTAssertEqual(mrPayload.objectAttributes.sourceBranch, "feature/test")
            XCTAssertEqual(mrPayload.objectAttributes.targetBranch, "main")
        } else {
            XCTFail("Expected mergeRequestHook event")
        }
    }

    func testParseEvent_mergeRequestHook_merge() async throws {
        let server = WebhookServer()
        let payload = makeMRHookPayload(action: "merge", state: "merged")
        let event = try await server.parseEvent(eventHeader: "Merge Request Hook", body: payload)

        if case .mergeRequestHook(let mrPayload) = event {
            XCTAssertEqual(mrPayload.objectAttributes.action, "merge")
            XCTAssertEqual(mrPayload.objectAttributes.state, "merged")
        } else {
            XCTFail("Expected mergeRequestHook event")
        }
    }

    func testParseEvent_mergeRequestHook_close() async throws {
        let server = WebhookServer()
        let payload = makeMRHookPayload(action: "close", state: "closed")
        let event = try await server.parseEvent(eventHeader: "Merge Request Hook", body: payload)

        if case .mergeRequestHook(let mrPayload) = event {
            XCTAssertEqual(mrPayload.objectAttributes.action, "close")
            XCTAssertEqual(mrPayload.objectAttributes.state, "closed")
        } else {
            XCTFail("Expected mergeRequestHook event")
        }
    }

    // MARK: - Push Hook Parsing Tests

    func testParseEvent_pushHook_normalPush() async throws {
        let server = WebhookServer()
        let payload = makePushHookPayload(
            ref: "refs/heads/feature/new-feature",
            before: "abc123",
            after: "def456"
        )
        let event = try await server.parseEvent(eventHeader: "Push Hook", body: payload)

        if case .pushHook(let pushPayload) = event {
            XCTAssertEqual(pushPayload.branchName, "feature/new-feature")
            XCTAssertFalse(pushPayload.isBranchDeletion)
            XCTAssertFalse(pushPayload.isBranchCreation)
            XCTAssertEqual(pushPayload.projectId, 100)
        } else {
            XCTFail("Expected pushHook event")
        }
    }

    func testParseEvent_pushHook_branchCreation() async throws {
        let server = WebhookServer()
        let payload = makePushHookPayload(
            ref: "refs/heads/new-branch",
            before: "0000000000000000000000000000000000000000",
            after: "abc123"
        )
        let event = try await server.parseEvent(eventHeader: "Push Hook", body: payload)

        if case .pushHook(let pushPayload) = event {
            XCTAssertEqual(pushPayload.branchName, "new-branch")
            XCTAssertTrue(pushPayload.isBranchCreation)
            XCTAssertFalse(pushPayload.isBranchDeletion)
        } else {
            XCTFail("Expected pushHook event")
        }
    }

    func testParseEvent_pushHook_branchDeletion() async throws {
        let server = WebhookServer()
        let payload = makePushHookPayload(
            ref: "refs/heads/old-branch",
            before: "abc123",
            after: "0000000000000000000000000000000000000000"
        )
        let event = try await server.parseEvent(eventHeader: "Push Hook", body: payload)

        if case .pushHook(let pushPayload) = event {
            XCTAssertEqual(pushPayload.branchName, "old-branch")
            XCTAssertTrue(pushPayload.isBranchDeletion)
            XCTAssertFalse(pushPayload.isBranchCreation)
        } else {
            XCTFail("Expected pushHook event")
        }
    }

    // MARK: - Pipeline Hook Parsing Tests

    func testParseEvent_pipelineHook_success() async throws {
        let server = WebhookServer()
        let payload = makePipelineHookPayload(status: "success")
        let event = try await server.parseEvent(eventHeader: "Pipeline Hook", body: payload)

        if case .pipelineHook(let pipelinePayload) = event {
            XCTAssertEqual(pipelinePayload.objectAttributes.status, "success")
            XCTAssertEqual(pipelinePayload.objectAttributes.id, 200)
            XCTAssertEqual(pipelinePayload.objectAttributes.ref, "main")
        } else {
            XCTFail("Expected pipelineHook event")
        }
    }

    func testParseEvent_pipelineHook_failed() async throws {
        let server = WebhookServer()
        let payload = makePipelineHookPayload(status: "failed")
        let event = try await server.parseEvent(eventHeader: "Pipeline Hook", body: payload)

        if case .pipelineHook(let pipelinePayload) = event {
            XCTAssertEqual(pipelinePayload.objectAttributes.status, "failed")
        } else {
            XCTFail("Expected pipelineHook event")
        }
    }

    func testParseEvent_pipelineHook_running() async throws {
        let server = WebhookServer()
        let payload = makePipelineHookPayload(status: "running")
        let event = try await server.parseEvent(eventHeader: "Pipeline Hook", body: payload)

        if case .pipelineHook(let pipelinePayload) = event {
            XCTAssertEqual(pipelinePayload.objectAttributes.status, "running")
        } else {
            XCTFail("Expected pipelineHook event")
        }
    }

    // MARK: - Duplicate Event Detection Tests

    func testDuplicateDetection_firstEvent_notDuplicate() async {
        let server = WebhookServer()
        let isDuplicate = await server.isDuplicateEvent(
            eventType: "issue",
            objectId: 42,
            updatedAt: "2024-01-15T10:00:00Z"
        )
        XCTAssertFalse(isDuplicate)
    }

    func testDuplicateDetection_sameEvent_isDuplicate() async {
        let server = WebhookServer()

        // First time - not duplicate
        let first = await server.isDuplicateEvent(
            eventType: "issue",
            objectId: 42,
            updatedAt: "2024-01-15T10:00:00Z"
        )
        XCTAssertFalse(first)

        // Second time - duplicate
        let second = await server.isDuplicateEvent(
            eventType: "issue",
            objectId: 42,
            updatedAt: "2024-01-15T10:00:00Z"
        )
        XCTAssertTrue(second)
    }

    func testDuplicateDetection_sameIdDifferentTimestamp_notDuplicate() async {
        let server = WebhookServer()

        let first = await server.isDuplicateEvent(
            eventType: "issue",
            objectId: 42,
            updatedAt: "2024-01-15T10:00:00Z"
        )
        XCTAssertFalse(first)

        // Same ID but different updated_at - not a duplicate
        let second = await server.isDuplicateEvent(
            eventType: "issue",
            objectId: 42,
            updatedAt: "2024-01-15T11:00:00Z"
        )
        XCTAssertFalse(second)
    }

    func testDuplicateDetection_differentEventTypes_notDuplicate() async {
        let server = WebhookServer()

        let first = await server.isDuplicateEvent(
            eventType: "issue",
            objectId: 42,
            updatedAt: "2024-01-15T10:00:00Z"
        )
        XCTAssertFalse(first)

        // Same ID and timestamp but different event type
        let second = await server.isDuplicateEvent(
            eventType: "merge_request",
            objectId: 42,
            updatedAt: "2024-01-15T10:00:00Z"
        )
        XCTAssertFalse(second)
    }

    // MARK: - Malformed Payload Tests

    func testParseEvent_malformedJSON_throwsError() async throws {
        let server = WebhookServer()
        let invalidData = "not valid json".data(using: .utf8)!

        do {
            _ = try await server.parseEvent(eventHeader: "Issue Hook", body: invalidData)
            XCTFail("Expected error for malformed payload")
        } catch let error as WebhookError {
            if case .malformedPayload = error {
                // Expected
            } else {
                XCTFail("Expected malformedPayload error, got: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testParseEvent_unknownEventType_throwsError() async throws {
        let server = WebhookServer()
        let data = "{}".data(using: .utf8)!

        do {
            _ = try await server.parseEvent(eventHeader: "Unknown Hook", body: data)
            XCTFail("Expected error for unknown event type")
        } catch let error as WebhookError {
            if case .unknownEventType(let type) = error {
                XCTAssertEqual(type, "Unknown Hook")
            } else {
                XCTFail("Expected unknownEventType error, got: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testParseEvent_incompletePayload_throwsError() async throws {
        let server = WebhookServer()
        // Valid JSON but missing required fields
        let incompleteData = """
        {"object_kind": "issue"}
        """.data(using: .utf8)!

        do {
            _ = try await server.parseEvent(eventHeader: "Issue Hook", body: incompleteData)
            XCTFail("Expected error for incomplete payload")
        } catch let error as WebhookError {
            if case .malformedPayload = error {
                // Expected
            } else {
                XCTFail("Expected malformedPayload error, got: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Deduplication Info Tests

    func testDeduplicationInfo_issueHook() async throws {
        let server = WebhookServer()
        let payload = makeIssueHookPayload(action: "update")
        let event = try await server.parseEvent(eventHeader: "Issue Hook", body: payload)

        let info = await server.deduplicationInfo(for: event)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.eventType, "issue")
        XCTAssertEqual(info?.objectId, 42)
        XCTAssertEqual(info?.updatedAt, "2024-01-15T10:30:00Z")
    }

    func testDeduplicationInfo_mergeRequestHook() async throws {
        let server = WebhookServer()
        let payload = makeMRHookPayload(action: "open", state: "opened")
        let event = try await server.parseEvent(eventHeader: "Merge Request Hook", body: payload)

        let info = await server.deduplicationInfo(for: event)
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.eventType, "merge_request")
        XCTAssertEqual(info?.objectId, 99)
    }

    func testDeduplicationInfo_pushHook_returnsNil() async throws {
        let server = WebhookServer()
        let payload = makePushHookPayload(ref: "refs/heads/main", before: "abc", after: "def")
        let event = try await server.parseEvent(eventHeader: "Push Hook", body: payload)

        let info = await server.deduplicationInfo(for: event)
        XCTAssertNil(info)
    }

    // MARK: - Server Lifecycle Tests

    func testServerStart_bindsToPort() async throws {
        let server = WebhookServer()
        try await server.start(port: 9876)

        let isRunning = await server.isRunning
        let port = await server.boundPort

        XCTAssertTrue(isRunning)
        XCTAssertNotNil(port)
        XCTAssertTrue(AppConstants.webhookPortRange.contains(port!))

        await server.stop()

        let isRunningAfterStop = await server.isRunning
        XCTAssertFalse(isRunningAfterStop)
    }

    func testServerStart_fallsToNextPort_whenPortOccupied() async throws {
        // Start first server on default port
        let server1 = WebhookServer()
        try await server1.start(port: 9876)
        let port1 = await server1.boundPort
        XCTAssertEqual(port1, 9876)

        // Start second server - should fall back to next port
        let server2 = WebhookServer()
        try await server2.start(port: 9876)
        let port2 = await server2.boundPort
        XCTAssertNotNil(port2)
        XCTAssertNotEqual(port2, 9876)
        XCTAssertTrue(AppConstants.webhookPortRange.contains(port2!))

        await server1.stop()
        await server2.stop()
    }

    func testServerStart_throwsWhenAlreadyRunning() async throws {
        let server = WebhookServer()
        try await server.start(port: 9876)

        do {
            try await server.start(port: 9877)
            XCTFail("Expected serverAlreadyRunning error")
        } catch let error as WebhookError {
            if case .serverAlreadyRunning = error {
                // Expected
            } else {
                XCTFail("Expected serverAlreadyRunning error, got: \(error)")
            }
        }

        await server.stop()
    }

    func testServerStop_whenNotRunning_doesNothing() async {
        let server = WebhookServer()
        // Should not crash
        await server.stop()
        let isRunning = await server.isRunning
        XCTAssertFalse(isRunning)
    }

    // MARK: - Event Handler Integration Tests

    func testHandleRequest_validEvent_callsHandler() async throws {
        let expectation = XCTestExpectation(description: "Event handler called")
        var receivedEvent: WebhookEvent?

        let server = WebhookServer(secretToken: "test-token") { event in
            receivedEvent = event
            expectation.fulfill()
        }

        let payload = makeIssueHookPayload(action: "update")
        await server.handleRequest(
            eventHeader: "Issue Hook",
            tokenHeader: "test-token",
            body: payload
        )

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertNotNil(receivedEvent)
        if case .issueHook(let issuePayload) = receivedEvent {
            XCTAssertEqual(issuePayload.objectAttributes.action, "update")
        } else {
            XCTFail("Expected issueHook event")
        }
    }

    func testHandleRequest_invalidToken_doesNotCallHandler() async {
        var handlerCalled = false

        let server = WebhookServer(secretToken: "correct-token") { _ in
            handlerCalled = true
        }

        let payload = makeIssueHookPayload(action: "update")
        await server.handleRequest(
            eventHeader: "Issue Hook",
            tokenHeader: "wrong-token",
            body: payload
        )

        // Give a moment for any async processing
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(handlerCalled)
    }

    func testHandleRequest_duplicateEvent_doesNotCallHandlerTwice() async throws {
        var callCount = 0

        let server = WebhookServer(secretToken: nil) { _ in
            callCount += 1
        }

        let payload = makeIssueHookPayload(action: "update")

        // First call - should invoke handler
        await server.handleRequest(eventHeader: "Issue Hook", tokenHeader: nil, body: payload)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(callCount, 1)

        // Second call with same payload - should be deduplicated
        await server.handleRequest(eventHeader: "Issue Hook", tokenHeader: nil, body: payload)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(callCount, 1)
    }

    func testHandleRequest_malformedPayload_doesNotCallHandler() async {
        var handlerCalled = false

        let server = WebhookServer(secretToken: nil) { _ in
            handlerCalled = true
        }

        let invalidData = "not json".data(using: .utf8)!
        await server.handleRequest(eventHeader: "Issue Hook", tokenHeader: nil, body: invalidData)

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(handlerCalled)
    }

    func testHandleRequest_missingEventHeader_doesNotCallHandler() async {
        var handlerCalled = false

        let server = WebhookServer(secretToken: nil) { _ in
            handlerCalled = true
        }

        let payload = makeIssueHookPayload(action: "update")
        await server.handleRequest(eventHeader: nil, tokenHeader: nil, body: payload)

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(handlerCalled)
    }

    // MARK: - HTTP Integration Test

    func testHTTPEndpoint_receivesWebhook() async throws {
        let expectation = XCTestExpectation(description: "Webhook received via HTTP")
        var receivedEvent: WebhookEvent?

        let server = WebhookServer(secretToken: "http-test-token") { event in
            receivedEvent = event
            expectation.fulfill()
        }

        try await server.start(port: 9876)
        let port = await server.boundPort ?? 9876

        // Send HTTP request to the server
        let url = URL(string: "http://127.0.0.1:\(port)/webhook")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Issue Hook", forHTTPHeaderField: "X-Gitlab-Event")
        request.setValue("http-test-token", forHTTPHeaderField: "X-Gitlab-Token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeIssueHookPayload(action: "open")

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = response as! HTTPURLResponse
        XCTAssertEqual(httpResponse.statusCode, 200)

        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertNotNil(receivedEvent)

        await server.stop()
    }

    func testHTTPEndpoint_healthCheck() async throws {
        let server = WebhookServer()
        try await server.start(port: 9876)
        let port = await server.boundPort ?? 9876

        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = response as! HTTPURLResponse

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(String(data: data, encoding: .utf8), "OK")

        await server.stop()
    }

    // MARK: - Test Payload Helpers

    private func makeIssueHookPayload(action: String, state: String = "opened") -> Data {
        let json = """
        {
            "object_kind": "issue",
            "event_type": "issue",
            "object_attributes": {
                "id": 42,
                "iid": 7,
                "title": "Test Issue",
                "description": "A test issue description",
                "state": "\(state)",
                "action": "\(action)",
                "weight": 5,
                "labels": [
                    {"id": 1, "title": "bug", "color": "#FF0000"}
                ],
                "updated_at": "2024-01-15T10:30:00Z",
                "created_at": "2024-01-15T09:00:00Z"
            },
            "project": {
                "id": 100,
                "name": "Test Project",
                "web_url": "https://gitlab.com/test/project",
                "path_with_namespace": "test/project"
            }
        }
        """
        return json.data(using: .utf8)!
    }

    private func makeMRHookPayload(action: String, state: String) -> Data {
        let json = """
        {
            "object_kind": "merge_request",
            "event_type": "merge_request",
            "object_attributes": {
                "id": 99,
                "iid": 15,
                "title": "Test MR",
                "description": "A test merge request",
                "state": "\(state)",
                "action": "\(action)",
                "source_branch": "feature/test",
                "target_branch": "main",
                "author_id": 5,
                "updated_at": "2024-01-15T11:00:00Z",
                "created_at": "2024-01-15T08:00:00Z"
            },
            "project": {
                "id": 100,
                "name": "Test Project",
                "web_url": "https://gitlab.com/test/project",
                "path_with_namespace": "test/project"
            }
        }
        """
        return json.data(using: .utf8)!
    }

    private func makePushHookPayload(ref: String, before: String, after: String) -> Data {
        let json = """
        {
            "object_kind": "push",
            "event_name": "push",
            "ref": "\(ref)",
            "before": "\(before)",
            "after": "\(after)",
            "project_id": 100,
            "project": {
                "id": 100,
                "name": "Test Project",
                "web_url": "https://gitlab.com/test/project",
                "path_with_namespace": "test/project"
            },
            "commits": [
                {
                    "id": "abc123def456",
                    "message": "Test commit",
                    "timestamp": "2024-01-15T10:00:00Z",
                    "url": "https://gitlab.com/test/project/-/commit/abc123def456",
                    "author": {
                        "name": "Test User",
                        "email": "test@example.com"
                    },
                    "added": ["new_file.swift"],
                    "modified": ["existing_file.swift"],
                    "removed": []
                }
            ],
            "total_commits_count": 1
        }
        """
        return json.data(using: .utf8)!
    }

    private func makePipelineHookPayload(status: String) -> Data {
        let json = """
        {
            "object_kind": "pipeline",
            "object_attributes": {
                "id": 200,
                "ref": "main",
                "status": "\(status)",
                "sha": "abc123def456789",
                "source": "push",
                "created_at": "2024-01-15T10:00:00Z",
                "finished_at": "2024-01-15T10:05:00Z"
            },
            "project": {
                "id": 100,
                "name": "Test Project",
                "web_url": "https://gitlab.com/test/project",
                "path_with_namespace": "test/project"
            },
            "merge_request": {
                "id": 99,
                "iid": 15,
                "title": "Test MR",
                "source_branch": "feature/test",
                "target_branch": "main"
            }
        }
        """
        return json.data(using: .utf8)!
    }
}
