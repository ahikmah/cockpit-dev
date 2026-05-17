import XCTest
@testable import CockpitDev

final class AIServiceTests: XCTestCase {

    private var service: AIService!
    private var encryptionService: EncryptionService!

    override func setUp() {
        super.setUp()
        encryptionService = EncryptionService(serviceIdentifier: "com.cockpitdev.tests.ai.\(UUID().uuidString)")
        service = AIService(
            endpoint: URL(string: "https://api.example.com/v1")!,
            timeout: 30,
            encryptionService: encryptionService
        )
    }

    override func tearDown() {
        service = nil
        encryptionService = nil
        super.tearDown()
    }

    // MARK: - Breakdown Response Parsing Tests

    func testParseBreakdownResponseValidJSON() async throws {
        let json = """
        {
          "tickets": [
            {
              "title": "Implement user authentication",
              "description": "Add OAuth2 login flow with token management",
              "priority": "high",
              "story_points": 8,
              "skill_classification": "beHeavy",
              "dependencies": []
            },
            {
              "title": "Create login UI",
              "description": "Build the login screen with email/password fields",
              "priority": "medium",
              "story_points": 3,
              "skill_classification": "feHeavy",
              "dependencies": ["Implement user authentication"]
            }
          ]
        }
        """

        let tickets = try await service.parseBreakdownResponse(json)

        XCTAssertEqual(tickets.count, 2)

        XCTAssertEqual(tickets[0].title, "Implement user authentication")
        XCTAssertEqual(tickets[0].description, "Add OAuth2 login flow with token management")
        XCTAssertEqual(tickets[0].priority, .high)
        XCTAssertEqual(tickets[0].estimatedStoryPoints, 8)
        XCTAssertEqual(tickets[0].skillClassification, .beHeavy)
        XCTAssertEqual(tickets[0].suggestedDependencies, [])

        XCTAssertEqual(tickets[1].title, "Create login UI")
        XCTAssertEqual(tickets[1].priority, .medium)
        XCTAssertEqual(tickets[1].estimatedStoryPoints, 3)
        XCTAssertEqual(tickets[1].skillClassification, .feHeavy)
        XCTAssertEqual(tickets[1].suggestedDependencies, ["Implement user authentication"])
    }

    func testParseBreakdownResponseWithMarkdownCodeFence() async throws {
        let json = """
        ```json
        {
          "tickets": [
            {
              "title": "Setup database",
              "description": "Configure PostgreSQL with migrations",
              "priority": "critical",
              "story_points": 5,
              "skill_classification": "beHeavy",
              "dependencies": []
            }
          ]
        }
        ```
        """

        let tickets = try await service.parseBreakdownResponse(json)

        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets[0].title, "Setup database")
        XCTAssertEqual(tickets[0].priority, .critical)
        XCTAssertEqual(tickets[0].estimatedStoryPoints, 5)
        XCTAssertEqual(tickets[0].skillClassification, .beHeavy)
    }

    func testParseBreakdownResponseNormalizesStoryPoints() async throws {
        let json = """
        {
          "tickets": [
            {
              "title": "Task with non-fibonacci SP",
              "description": "Should normalize to nearest fibonacci",
              "priority": "low",
              "story_points": 4,
              "skill_classification": "fullstack",
              "dependencies": []
            },
            {
              "title": "Task with valid SP",
              "description": "Should keep as-is",
              "priority": "medium",
              "story_points": 13,
              "skill_classification": "fullstack",
              "dependencies": []
            }
          ]
        }
        """

        let tickets = try await service.parseBreakdownResponse(json)

        // 4 is between 3 and 5, should normalize to nearest (either 3 or 5)
        XCTAssertTrue(AppConstants.fibonacciSequence.contains(tickets[0].estimatedStoryPoints))
        // 13 is already fibonacci
        XCTAssertEqual(tickets[1].estimatedStoryPoints, 13)
    }

    func testParseBreakdownResponseHandlesAlternativeSkillNames() async throws {
        let json = """
        {
          "tickets": [
            {
              "title": "Backend task",
              "description": "Test",
              "priority": "medium",
              "story_points": 3,
              "skill_classification": "backend",
              "dependencies": []
            },
            {
              "title": "Frontend task",
              "description": "Test",
              "priority": "medium",
              "story_points": 3,
              "skill_classification": "frontend",
              "dependencies": []
            },
            {
              "title": "Full stack task",
              "description": "Test",
              "priority": "medium",
              "story_points": 3,
              "skill_classification": "full_stack",
              "dependencies": []
            }
          ]
        }
        """

        let tickets = try await service.parseBreakdownResponse(json)

        XCTAssertEqual(tickets[0].skillClassification, .beHeavy)
        XCTAssertEqual(tickets[1].skillClassification, .feHeavy)
        XCTAssertEqual(tickets[2].skillClassification, .fullstack)
    }

    func testParseBreakdownResponseHandlesUnknownPriority() async throws {
        let json = """
        {
          "tickets": [
            {
              "title": "Unknown priority task",
              "description": "Test",
              "priority": "urgent",
              "story_points": 5,
              "skill_classification": "fullstack",
              "dependencies": []
            }
          ]
        }
        """

        let tickets = try await service.parseBreakdownResponse(json)

        // Unknown priority defaults to medium
        XCTAssertEqual(tickets[0].priority, .medium)
    }

    func testParseBreakdownResponseHandlesNullDependencies() async throws {
        let json = """
        {
          "tickets": [
            {
              "title": "Task without deps",
              "description": "Test",
              "priority": "low",
              "story_points": 1,
              "skill_classification": "fullstack"
            }
          ]
        }
        """

        let tickets = try await service.parseBreakdownResponse(json)

        XCTAssertEqual(tickets[0].suggestedDependencies, [])
    }

    func testParseBreakdownResponseInvalidJSONThrows() async {
        let invalidJSON = "This is not JSON at all"

        do {
            _ = try await service.parseBreakdownResponse(invalidJSON)
            XCTFail("Expected parsing to throw")
        } catch {
            XCTAssertTrue(error is AIServiceError)
            if case AIServiceError.parsingFailed = error {
                // Expected
            } else {
                XCTFail("Expected parsingFailed error, got \(error)")
            }
        }
    }

    func testParseBreakdownResponseEmptyTicketsArray() async throws {
        let json = """
        {
          "tickets": []
        }
        """

        let tickets = try await service.parseBreakdownResponse(json)
        XCTAssertEqual(tickets.count, 0)
    }

    // MARK: - Re-Evaluation Response Parsing Tests

    func testParseReEvaluationResponseValid() async throws {
        let json = """
        {
          "new_tickets": [
            {
              "title": "New feature X",
              "description": "Implement feature X",
              "priority": "high",
              "story_points": 8,
              "skill_classification": "fullstack",
              "dependencies": []
            }
          ],
          "changed_tickets": [
            {
              "existing_title": "Old task name",
              "suggested": {
                "title": "Updated task name",
                "description": "Updated description",
                "priority": "medium",
                "story_points": 5,
                "skill_classification": "beHeavy",
                "dependencies": ["New feature X"]
              }
            }
          ],
          "removed_tickets": ["Deprecated feature"],
          "unchanged_tickets": ["Core setup", "Database migration"]
        }
        """

        let result = try await service.parseReEvaluationResponse(json)

        XCTAssertEqual(result.newTickets.count, 1)
        XCTAssertEqual(result.newTickets[0].title, "New feature X")
        XCTAssertEqual(result.newTickets[0].priority, .high)
        XCTAssertEqual(result.newTickets[0].estimatedStoryPoints, 8)

        XCTAssertEqual(result.changedTickets.count, 1)
        XCTAssertEqual(result.changedTickets[0].existingTitle, "Old task name")
        XCTAssertEqual(result.changedTickets[0].suggested.title, "Updated task name")
        XCTAssertEqual(result.changedTickets[0].suggested.skillClassification, .beHeavy)

        XCTAssertEqual(result.removedTicketTitles, ["Deprecated feature"])
        XCTAssertEqual(result.unchangedTicketTitles, ["Core setup", "Database migration"])
    }

    func testParseReEvaluationResponseWithCodeFence() async throws {
        let json = """
        ```json
        {
          "new_tickets": [],
          "changed_tickets": [],
          "removed_tickets": ["Old feature"],
          "unchanged_tickets": ["Existing feature"]
        }
        ```
        """

        let result = try await service.parseReEvaluationResponse(json)

        XCTAssertEqual(result.newTickets.count, 0)
        XCTAssertEqual(result.changedTickets.count, 0)
        XCTAssertEqual(result.removedTicketTitles, ["Old feature"])
        XCTAssertEqual(result.unchangedTicketTitles, ["Existing feature"])
    }

    func testParseReEvaluationResponseInvalidJSONThrows() async {
        let invalidJSON = "not valid json"

        do {
            _ = try await service.parseReEvaluationResponse(invalidJSON)
            XCTFail("Expected parsing to throw")
        } catch {
            XCTAssertTrue(error is AIServiceError)
        }
    }

    // MARK: - API Key Management Tests

    func testStoreAndRetrieveAPIKey() async throws {
        let apiKey = "sk-test-key-12345"

        try await service.storeAPIKey(apiKey)
        let retrieved = await service.retrieveAPIKey()

        XCTAssertEqual(retrieved, apiKey)

        // Cleanup
        try await service.deleteAPIKey()
    }

    func testRetrieveAPIKeyWhenNoneStored() async {
        let retrieved = await service.retrieveAPIKey()
        XCTAssertNil(retrieved)
    }

    func testMaskedAPIKey() async throws {
        let apiKey = "sk-test-key-abcdef1234"
        try await service.storeAPIKey(apiKey)

        let masked = await service.maskedAPIKey()
        XCTAssertEqual(masked, "****1234")
        XCTAssertFalse(masked.contains("sk-test"))

        // Cleanup
        try await service.deleteAPIKey()
    }

    func testMaskedAPIKeyWhenNoneStored() async {
        let masked = await service.maskedAPIKey()
        XCTAssertEqual(masked, "")
    }

    // MARK: - Configuration Tests

    func testSetEndpoint() async {
        let newEndpoint = URL(string: "https://new-api.example.com/v1")!
        await service.setEndpoint(newEndpoint)

        let endpoint = await service.getEndpoint()
        XCTAssertEqual(endpoint, newEndpoint)
    }

    func testSetTimeout() async {
        await service.setTimeout(60)

        let timeout = await service.getTimeout()
        XCTAssertEqual(timeout, 60)
    }

    func testDefaultTimeout() async {
        let timeout = await service.getTimeout()
        XCTAssertEqual(timeout, 30) // We set 30 in setUp
    }

    // MARK: - GeneratedTicket Equatable Tests

    func testGeneratedTicketEquality() {
        let id = UUID()
        let ticket1 = GeneratedTicket(
            id: id,
            title: "Test",
            description: "Desc",
            priority: .high,
            estimatedStoryPoints: 5,
            skillClassification: .beHeavy,
            suggestedDependencies: ["A"]
        )
        let ticket2 = GeneratedTicket(
            id: id,
            title: "Test",
            description: "Desc",
            priority: .high,
            estimatedStoryPoints: 5,
            skillClassification: .beHeavy,
            suggestedDependencies: ["A"]
        )

        XCTAssertEqual(ticket1, ticket2)
    }

    func testGeneratedTicketInequality() {
        let ticket1 = GeneratedTicket(
            title: "Test 1",
            description: "Desc",
            priority: .high,
            estimatedStoryPoints: 5,
            skillClassification: .beHeavy
        )
        let ticket2 = GeneratedTicket(
            title: "Test 2",
            description: "Desc",
            priority: .high,
            estimatedStoryPoints: 5,
            skillClassification: .beHeavy
        )

        XCTAssertNotEqual(ticket1, ticket2)
    }

    // MARK: - Multiple Tickets Parsing

    func testParseBreakdownResponseMultipleTickets() async throws {
        let json = """
        {
          "tickets": [
            {
              "title": "Task 1",
              "description": "First task",
              "priority": "critical",
              "story_points": 13,
              "skill_classification": "beHeavy",
              "dependencies": []
            },
            {
              "title": "Task 2",
              "description": "Second task",
              "priority": "high",
              "story_points": 8,
              "skill_classification": "feHeavy",
              "dependencies": ["Task 1"]
            },
            {
              "title": "Task 3",
              "description": "Third task",
              "priority": "medium",
              "story_points": 5,
              "skill_classification": "fullstack",
              "dependencies": ["Task 1", "Task 2"]
            },
            {
              "title": "Task 4",
              "description": "Fourth task",
              "priority": "low",
              "story_points": 2,
              "skill_classification": "feHeavy",
              "dependencies": []
            }
          ]
        }
        """

        let tickets = try await service.parseBreakdownResponse(json)

        XCTAssertEqual(tickets.count, 4)
        XCTAssertEqual(tickets[0].priority, .critical)
        XCTAssertEqual(tickets[1].priority, .high)
        XCTAssertEqual(tickets[2].priority, .medium)
        XCTAssertEqual(tickets[3].priority, .low)
        XCTAssertEqual(tickets[2].suggestedDependencies.count, 2)
    }

    // MARK: - Edge Cases

    func testParseBreakdownResponseWithExtraWhitespace() async throws {
        let json = """

            {
              "tickets": [
                {
                  "title": "  Trimmed title  ",
                  "description": "Description with spaces",
                  "priority": "medium",
                  "story_points": 3,
                  "skill_classification": "fullstack",
                  "dependencies": []
                }
              ]
            }

        """

        let tickets = try await service.parseBreakdownResponse(json)
        XCTAssertEqual(tickets.count, 1)
        // Note: title preserves whitespace from JSON (trimming is UI responsibility)
        XCTAssertEqual(tickets[0].title, "  Trimmed title  ")
    }

    func testParseBreakdownResponseStoryPointsNormalization() async throws {
        // Test various non-fibonacci values
        let json = """
        {
          "tickets": [
            {
              "title": "SP 0",
              "description": "Test",
              "priority": "low",
              "story_points": 0,
              "skill_classification": "fullstack",
              "dependencies": []
            },
            {
              "title": "SP 10",
              "description": "Test",
              "priority": "low",
              "story_points": 10,
              "skill_classification": "fullstack",
              "dependencies": []
            },
            {
              "title": "SP 21",
              "description": "Test",
              "priority": "low",
              "story_points": 21,
              "skill_classification": "fullstack",
              "dependencies": []
            },
            {
              "title": "SP 100",
              "description": "Test",
              "priority": "low",
              "story_points": 100,
              "skill_classification": "fullstack",
              "dependencies": []
            }
          ]
        }
        """

        let tickets = try await service.parseBreakdownResponse(json)

        // All should be valid fibonacci numbers
        for ticket in tickets {
            XCTAssertTrue(
                AppConstants.fibonacciSequence.contains(ticket.estimatedStoryPoints),
                "Story points \(ticket.estimatedStoryPoints) for '\(ticket.title)' is not in fibonacci sequence"
            )
        }

        // 0 → nearest is 1
        XCTAssertEqual(tickets[0].estimatedStoryPoints, 1)
        // 10 → nearest is 8 or 13 (8 is closer: |10-8|=2 vs |10-13|=3)
        XCTAssertEqual(tickets[1].estimatedStoryPoints, 8)
        // 21 → already fibonacci
        XCTAssertEqual(tickets[2].estimatedStoryPoints, 21)
        // 100 → nearest is 21
        XCTAssertEqual(tickets[3].estimatedStoryPoints, 21)
    }
}
