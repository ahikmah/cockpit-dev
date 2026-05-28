import XCTest
@testable import CockpitDev

/// Unit tests for AutoAssignService covering scoring, threshold enforcement, and edge cases.
final class AutoAssignServiceTests: CockpitDevTestCase {

    private var service: AutoAssignService!

    override func setUp() {
        super.setUp()
        service = AutoAssignService()
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    // MARK: - Helper Factories

    private func makeMember(
        displayName: String = "Dev",
        skillProfile: SkillProfile? = nil,
        gitlabUserId: Int = 1
    ) -> Member {
        Member(
            gitlabUserId: gitlabUserId,
            username: displayName.lowercased().replacingOccurrences(of: " ", with: "_"),
            displayName: displayName,
            skillProfile: skillProfile
        )
    }

    private func makeTicket(
        title: String = "Test Ticket",
        descriptionText: String? = nil,
        storyPoints: Int? = 5,
        labels: [String] = [],
        assignee: Member? = nil
    ) -> Ticket {
        let ticket = Ticket(
            title: title,
            descriptionText: descriptionText,
            storyPoints: storyPoints,
            labels: labels
        )
        ticket.assignee = assignee
        return ticket
    }

    private func makeSprint(tickets: [Ticket] = []) -> Sprint {
        let sprint = Sprint(
            name: "Sprint 1",
            startDate: Date(),
            endDate: Date().addingTimeInterval(14 * 24 * 3600)
        )
        sprint.tickets = tickets
        return sprint
    }

    // MARK: - classifyTicket Tests

    func testClassifyTicketWithBackendLabels() {
        let ticket = makeTicket(labels: ["api", "backend"])
        let result = service.classifyTicket(ticket)
        XCTAssertEqual(result, .beHeavy)
    }

    func testClassifyTicketWithFrontendLabels() {
        let ticket = makeTicket(labels: ["ui", "frontend"])
        let result = service.classifyTicket(ticket)
        XCTAssertEqual(result, .feHeavy)
    }

    func testClassifyTicketWithMixedLabelsAsFullstack() {
        let ticket = makeTicket(labels: ["api", "ui"])
        let result = service.classifyTicket(ticket)
        XCTAssertEqual(result, .fullstack)
    }

    func testClassifyTicketWithNoKeywordsAsFullstack() {
        let ticket = makeTicket(title: "Generic task", labels: [])
        let result = service.classifyTicket(ticket)
        XCTAssertEqual(result, .fullstack)
    }

    func testClassifyTicketByDescriptionKeywords() {
        let ticket = makeTicket(
            title: "Implement feature",
            descriptionText: "Create a new REST endpoint for the authentication service with database migration"
        )
        let result = service.classifyTicket(ticket)
        XCTAssertEqual(result, .beHeavy)
    }

    func testClassifyTicketByTitleKeywords() {
        let ticket = makeTicket(title: "Fix UI component layout issue")
        let result = service.classifyTicket(ticket)
        XCTAssertEqual(result, .feHeavy)
    }

    func testClassifyTicketFrontendDescription() {
        let ticket = makeTicket(
            title: "Update page",
            descriptionText: "Redesign the dashboard layout with new responsive component and animation"
        )
        let result = service.classifyTicket(ticket)
        XCTAssertEqual(result, .feHeavy)
    }

    // MARK: - skillFitScore Tests

    func testSkillFitExactMatchReturns10() {
        let member = makeMember(skillProfile: .beHeavy)
        let score = service.skillFitScore(member: member, ticketType: .beHeavy)
        XCTAssertEqual(score, 10)
    }

    func testSkillFitFullstackReturns5ForNonFullstackTicket() {
        let member = makeMember(skillProfile: .fullstack)

        let scoreBE = service.skillFitScore(member: member, ticketType: .beHeavy)
        let scoreFE = service.skillFitScore(member: member, ticketType: .feHeavy)

        XCTAssertEqual(scoreBE, 5)
        XCTAssertEqual(scoreFE, 5)
    }

    func testSkillFitFullstackExactMatchReturns10() {
        let member = makeMember(skillProfile: .fullstack)
        let score = service.skillFitScore(member: member, ticketType: .fullstack)
        XCTAssertEqual(score, 10)
    }

    func testSkillFitMismatchReturns0() {
        let member = makeMember(skillProfile: .beHeavy)
        let score = service.skillFitScore(member: member, ticketType: .feHeavy)
        XCTAssertEqual(score, 0)
    }

    func testSkillFitNoProfileReturns0() {
        let member = makeMember(skillProfile: nil)
        let score = service.skillFitScore(member: member, ticketType: .beHeavy)
        XCTAssertEqual(score, 0)
    }

    func testSkillFitFEExactMatchReturns10() {
        let member = makeMember(skillProfile: .feHeavy)
        let score = service.skillFitScore(member: member, ticketType: .feHeavy)
        XCTAssertEqual(score, 10)
    }

    // MARK: - computeAssignments Tests

    func testBasicAssignmentToBestFitMember() {
        let beMember = makeMember(displayName: "BE Dev", skillProfile: .beHeavy, gitlabUserId: 1)
        let feMember = makeMember(displayName: "FE Dev", skillProfile: .feHeavy, gitlabUserId: 2)

        let ticket = makeTicket(title: "Create API endpoint", storyPoints: 5, labels: ["api"])
        let sprint = makeSprint()

        let suggestions = service.computeAssignments(
            tickets: [ticket],
            members: [beMember, feMember],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].suggestedMember?.id, beMember.id)
        XCTAssertNil(suggestions[0].reason)
    }

    func testTicketsSortedByComplexityDescending() {
        let member = makeMember(displayName: "Dev", skillProfile: .fullstack, gitlabUserId: 1)

        let smallTicket = makeTicket(title: "Small task", storyPoints: 2)
        let largeTicket = makeTicket(title: "Large task", storyPoints: 13)
        let mediumTicket = makeTicket(title: "Medium task", storyPoints: 5)

        let sprint = makeSprint()

        let suggestions = service.computeAssignments(
            tickets: [smallTicket, largeTicket, mediumTicket],
            members: [member],
            sprint: sprint,
            maxThreshold: 21
        )

        let assignedSuggestions = suggestions.filter { $0.suggestedMember != nil }
        XCTAssertEqual(assignedSuggestions.count, 3)

        // First assigned should be the large ticket (13 SP)
        XCTAssertEqual(assignedSuggestions[0].ticket.storyPoints, 13)
        XCTAssertEqual(assignedSuggestions[1].ticket.storyPoints, 5)
        XCTAssertEqual(assignedSuggestions[2].ticket.storyPoints, 2)
    }

    func testWorkloadThresholdExcludesOverloadedMembers() {
        let member = makeMember(displayName: "Busy Dev", skillProfile: .fullstack, gitlabUserId: 1)

        // Member already has 21 SP assigned in sprint
        let existingTicket = makeTicket(title: "Existing", storyPoints: 21, assignee: member)
        let sprint = makeSprint(tickets: [existingTicket])

        let newTicket = makeTicket(title: "New task", storyPoints: 3)

        let suggestions = service.computeAssignments(
            tickets: [newTicket],
            members: [member],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertNil(suggestions[0].suggestedMember)
        XCTAssertNotNil(suggestions[0].reason)
        XCTAssertTrue(suggestions[0].reason!.contains("threshold"))
    }

    func testTicketsWithoutStoryPointsAreSkipped() {
        let member = makeMember(displayName: "Dev", skillProfile: .fullstack, gitlabUserId: 1)
        let ticket = makeTicket(title: "No SP ticket", storyPoints: nil)
        let sprint = makeSprint()

        let suggestions = service.computeAssignments(
            tickets: [ticket],
            members: [member],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertNil(suggestions[0].suggestedMember)
        XCTAssertNotNil(suggestions[0].reason)
        XCTAssertTrue(suggestions[0].reason!.contains("Story points are required"))
    }

    func testUnassignableTicketWhenNoSkillMatch() {
        let beMember = makeMember(displayName: "BE Dev", skillProfile: .beHeavy, gitlabUserId: 1)
        let ticket = makeTicket(title: "Build UI component", storyPoints: 5, labels: ["ui", "frontend"])
        let sprint = makeSprint()

        let suggestions = service.computeAssignments(
            tickets: [ticket],
            members: [beMember],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertNil(suggestions[0].suggestedMember)
        XCTAssertNotNil(suggestions[0].reason)
        XCTAssertTrue(suggestions[0].reason!.contains("skill profile"))
    }

    func testWorkloadDistributionAcrossMembers() {
        let member1 = makeMember(displayName: "Dev 1", skillProfile: .fullstack, gitlabUserId: 1)
        let member2 = makeMember(displayName: "Dev 2", skillProfile: .fullstack, gitlabUserId: 2)

        let ticket1 = makeTicket(title: "Task 1", storyPoints: 8)
        let ticket2 = makeTicket(title: "Task 2", storyPoints: 8)
        let ticket3 = makeTicket(title: "Task 3", storyPoints: 8)

        let sprint = makeSprint()

        let suggestions = service.computeAssignments(
            tickets: [ticket1, ticket2, ticket3],
            members: [member1, member2],
            sprint: sprint,
            maxThreshold: 21
        )

        let assigned = suggestions.filter { $0.suggestedMember != nil }
        XCTAssertEqual(assigned.count, 3)

        // Both members should get tickets (workload balancing)
        let member1Assignments = assigned.filter { $0.suggestedMember?.id == member1.id }
        let member2Assignments = assigned.filter { $0.suggestedMember?.id == member2.id }

        XCTAssertGreaterThanOrEqual(member1Assignments.count, 1)
        XCTAssertGreaterThanOrEqual(member2Assignments.count, 1)
    }

    func testMemberWithLessCapacityLosesToMemberWithMoreCapacity() {
        let member1 = makeMember(displayName: "Dev 1", skillProfile: .fullstack, gitlabUserId: 1)
        let member2 = makeMember(displayName: "Dev 2", skillProfile: .fullstack, gitlabUserId: 2)

        // Member1 already at 20 SP
        let existingTicket = makeTicket(title: "Existing", storyPoints: 20, assignee: member1)
        let sprint = makeSprint(tickets: [existingTicket])

        let newTicket = makeTicket(title: "New task", storyPoints: 5)

        let suggestions = service.computeAssignments(
            tickets: [newTicket],
            members: [member1, member2],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertEqual(suggestions.count, 1)
        // Member2 should win due to more capacity
        // Score for member1: (5*10) + (21-20) = 51
        // Score for member2: (5*10) + (21-0) = 71
        XCTAssertEqual(suggestions[0].suggestedMember?.id, member2.id)
    }

    func testEmptyTicketsReturnsEmptySuggestions() {
        let member = makeMember(displayName: "Dev", skillProfile: .fullstack, gitlabUserId: 1)
        let sprint = makeSprint()

        let suggestions = service.computeAssignments(
            tickets: [],
            members: [member],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertTrue(suggestions.isEmpty)
    }

    func testEmptyMembersMakesAllTicketsUnassignable() {
        let ticket = makeTicket(title: "Task", storyPoints: 5)
        let sprint = makeSprint()

        let suggestions = service.computeAssignments(
            tickets: [ticket],
            members: [],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertNil(suggestions[0].suggestedMember)
    }

    func testResultingWorkloadCalculation() {
        let member = makeMember(displayName: "Dev", skillProfile: .fullstack, gitlabUserId: 1)

        let existingTicket = makeTicket(title: "Existing", storyPoints: 8, assignee: member)
        let sprint = makeSprint(tickets: [existingTicket])

        let newTicket = makeTicket(title: "New task", storyPoints: 5)

        let suggestions = service.computeAssignments(
            tickets: [newTicket],
            members: [member],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].suggestedMember?.id, member.id)
        XCTAssertEqual(suggestions[0].resultingWorkload, 13) // 8 existing + 5 new
    }

    func testGreedyWorkloadAccumulation() {
        let member = makeMember(displayName: "Dev", skillProfile: .fullstack, gitlabUserId: 1)

        let ticket1 = makeTicket(title: "Task 1", storyPoints: 8)
        let ticket2 = makeTicket(title: "Task 2", storyPoints: 8)
        let ticket3 = makeTicket(title: "Task 3", storyPoints: 8)

        let sprint = makeSprint()

        let suggestions = service.computeAssignments(
            tickets: [ticket1, ticket2, ticket3],
            members: [member],
            sprint: sprint,
            maxThreshold: 21
        )

        let assigned = suggestions.filter { $0.suggestedMember != nil }

        // Member starts at 0, gets 8 (now 8), gets 8 (now 16), gets 8 (now 24)
        // All three should be assigned since 0, 8, 16 are all < 21
        XCTAssertEqual(assigned.count, 3)

        // Verify workload accumulation
        XCTAssertEqual(assigned[0].resultingWorkload, 8)
        XCTAssertEqual(assigned[1].resultingWorkload, 16)
        XCTAssertEqual(assigned[2].resultingWorkload, 24)
    }

    func testMixedTicketsSomeWithSPSomeWithout() {
        let member = makeMember(displayName: "Dev", skillProfile: .fullstack, gitlabUserId: 1)

        let ticketWithSP = makeTicket(title: "With SP", storyPoints: 5)
        let ticketWithoutSP = makeTicket(title: "Without SP", storyPoints: nil)

        let sprint = makeSprint()

        let suggestions = service.computeAssignments(
            tickets: [ticketWithSP, ticketWithoutSP],
            members: [member],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertEqual(suggestions.count, 2)

        let assigned = suggestions.filter { $0.suggestedMember != nil }
        let skipped = suggestions.filter { $0.reason?.contains("Story points") == true }

        XCTAssertEqual(assigned.count, 1)
        XCTAssertEqual(skipped.count, 1)
    }

    func testScoringFormulaPreference() {
        // Member with exact match and 0 workload: (10 × 10) + (21 - 0) = 121
        // Member with fullstack and 10 workload: (5 × 10) + (21 - 10) = 61
        let exactMember = makeMember(displayName: "Exact", skillProfile: .beHeavy, gitlabUserId: 1)
        let fullstackMember = makeMember(displayName: "Fullstack", skillProfile: .fullstack, gitlabUserId: 2)

        let existingTicket = makeTicket(title: "Existing", storyPoints: 10, assignee: fullstackMember)
        let sprint = makeSprint(tickets: [existingTicket])

        let ticket = makeTicket(title: "API endpoint", storyPoints: 5, labels: ["api", "backend"])

        let suggestions = service.computeAssignments(
            tickets: [ticket],
            members: [exactMember, fullstackMember],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertEqual(suggestions.count, 1)
        // Exact member should win: score 121 vs 61
        XCTAssertEqual(suggestions[0].suggestedMember?.id, exactMember.id)
    }

    func testMemberExactlyAtThresholdIsExcluded() {
        let member = makeMember(displayName: "Dev", skillProfile: .fullstack, gitlabUserId: 1)

        // Member exactly at threshold (21 SP)
        let existingTicket = makeTicket(title: "Existing", storyPoints: 21, assignee: member)
        let sprint = makeSprint(tickets: [existingTicket])

        let newTicket = makeTicket(title: "New task", storyPoints: 3)

        let suggestions = service.computeAssignments(
            tickets: [newTicket],
            members: [member],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertNil(suggestions[0].suggestedMember)
    }

    func testMemberJustBelowThresholdIsEligible() {
        let member = makeMember(displayName: "Dev", skillProfile: .fullstack, gitlabUserId: 1)

        // Member at 20 SP (just below 21 threshold)
        let existingTicket = makeTicket(title: "Existing", storyPoints: 20, assignee: member)
        let sprint = makeSprint(tickets: [existingTicket])

        let newTicket = makeTicket(title: "New task", storyPoints: 3)

        let suggestions = service.computeAssignments(
            tickets: [newTicket],
            members: [member],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].suggestedMember?.id, member.id)
        XCTAssertEqual(suggestions[0].resultingWorkload, 23) // 20 + 3
    }

    func testCustomThreshold() {
        let member = makeMember(displayName: "Dev", skillProfile: .fullstack, gitlabUserId: 1)

        // Member at 10 SP, threshold is 10
        let existingTicket = makeTicket(title: "Existing", storyPoints: 10, assignee: member)
        let sprint = makeSprint(tickets: [existingTicket])

        let newTicket = makeTicket(title: "New task", storyPoints: 3)

        let suggestions = service.computeAssignments(
            tickets: [newTicket],
            members: [member],
            sprint: sprint,
            maxThreshold: 10
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertNil(suggestions[0].suggestedMember) // At threshold, excluded
    }

    func testAllMembersWithNoSkillProfileMakesTicketUnassignable() {
        let member1 = makeMember(displayName: "Dev 1", skillProfile: nil, gitlabUserId: 1)
        let member2 = makeMember(displayName: "Dev 2", skillProfile: nil, gitlabUserId: 2)

        let ticket = makeTicket(title: "API task", storyPoints: 5, labels: ["api"])
        let sprint = makeSprint()

        let suggestions = service.computeAssignments(
            tickets: [ticket],
            members: [member1, member2],
            sprint: sprint,
            maxThreshold: 21
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertNil(suggestions[0].suggestedMember)
    }
}
