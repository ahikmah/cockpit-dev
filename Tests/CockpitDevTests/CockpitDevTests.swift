import XCTest
@testable import CockpitDev

final class CockpitDevTests: CockpitDevTestCase {

    // MARK: - Enum Tests

    func testMemberRoleRawValues() {
        XCTAssertEqual(MemberRole.owner.rawValue, "owner")
        XCTAssertEqual(MemberRole.admin.rawValue, "admin")
        XCTAssertEqual(MemberRole.member.rawValue, "member")
        XCTAssertEqual(MemberRole.viewer.rawValue, "viewer")
    }

    func testSkillProfileRawValues() {
        XCTAssertEqual(SkillProfile.beHeavy.rawValue, "beHeavy")
        XCTAssertEqual(SkillProfile.feHeavy.rawValue, "feHeavy")
        XCTAssertEqual(SkillProfile.fullstack.rawValue, "fullstack")
    }

    func testTicketStatusRawValues() {
        XCTAssertEqual(TicketStatus.backlog.rawValue, "backlog")
        XCTAssertEqual(TicketStatus.todo.rawValue, "todo")
        XCTAssertEqual(TicketStatus.inProgress.rawValue, "inProgress")
        XCTAssertEqual(TicketStatus.inReview.rawValue, "inReview")
        XCTAssertEqual(TicketStatus.done.rawValue, "done")
    }

    func testTicketPriorityRawValues() {
        XCTAssertEqual(TicketPriority.critical.rawValue, "critical")
        XCTAssertEqual(TicketPriority.high.rawValue, "high")
        XCTAssertEqual(TicketPriority.medium.rawValue, "medium")
        XCTAssertEqual(TicketPriority.low.rawValue, "low")
    }

    func testPipelineStatusRawValues() {
        XCTAssertEqual(PipelineStatus.running.rawValue, "running")
        XCTAssertEqual(PipelineStatus.success.rawValue, "success")
        XCTAssertEqual(PipelineStatus.failed.rawValue, "failed")
        XCTAssertEqual(PipelineStatus.canceled.rawValue, "canceled")
        XCTAssertEqual(PipelineStatus.pending.rawValue, "pending")
    }

    func testMRStateRawValues() {
        XCTAssertEqual(MRState.opened.rawValue, "opened")
        XCTAssertEqual(MRState.merged.rawValue, "merged")
        XCTAssertEqual(MRState.closed.rawValue, "closed")
    }

    func testSpecPhaseRawValues() {
        XCTAssertEqual(SpecPhase.proposal.rawValue, "proposal")
        XCTAssertEqual(SpecPhase.design.rawValue, "design")
        XCTAssertEqual(SpecPhase.tasks.rawValue, "tasks")
    }

    func testNotificationEventTypeRawValues() {
        XCTAssertEqual(NotificationEventType.newMergeRequest.rawValue, "newMergeRequest")
        XCTAssertEqual(NotificationEventType.mrApproval.rawValue, "mrApproval")
        XCTAssertEqual(NotificationEventType.dependencyConflict.rawValue, "dependencyConflict")
        XCTAssertEqual(NotificationEventType.sprintCompletion.rawValue, "sprintCompletion")
    }

    // MARK: - Constants Tests

    func testDefaultWebhookPort() {
        XCTAssertEqual(AppConstants.defaultWebhookPort, 9876)
    }

    func testMaxNotifications() {
        XCTAssertEqual(AppConstants.maxNotifications, 500)
    }

    func testDefaultPollInterval() {
        XCTAssertEqual(AppConstants.defaultPollInterval, 300)
    }

    func testFibonacciSequence() {
        XCTAssertEqual(AppConstants.fibonacciSequence, [1, 2, 3, 5, 8, 13, 21])
    }

    func testMaxStoryPointsThreshold() {
        XCTAssertEqual(AppConstants.maxStoryPointsThreshold, 21)
    }

    // MARK: - Enum Codable Tests

    func testMemberRoleCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let role = MemberRole.admin
        let data = try encoder.encode(role)
        let decoded = try decoder.decode(MemberRole.self, from: data)
        XCTAssertEqual(decoded, role)
    }

    func testTicketStatusCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let status = TicketStatus.inProgress
        let data = try encoder.encode(status)
        let decoded = try decoder.decode(TicketStatus.self, from: data)
        XCTAssertEqual(decoded, status)
    }

    func testNotificationEventTypeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let eventType = NotificationEventType.dependencyConflict
        let data = try encoder.encode(eventType)
        let decoded = try decoder.decode(NotificationEventType.self, from: data)
        XCTAssertEqual(decoded, eventType)
    }
}
