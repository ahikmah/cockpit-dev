import XCTest
@testable import CockpitDev

/// Tests for DependencyConflictEngine covering:
/// - Circular dependency validation (DAG enforcement)
/// - Schedule conflict detection
/// - Status conflict detection
/// - Workspace-wide and per-ticket evaluation
/// - Automatic conflict resolution
final class DependencyConflictEngineTests: CockpitDevTestCase {

    var engine: DependencyConflictEngine!

    override func setUp() {
        super.setUp()
        engine = DependencyConflictEngine()
    }

    override func tearDown() {
        engine = nil
        super.tearDown()
    }

    // MARK: - Circular Dependency Validation

    func testValidateNoCycle_noCycle_returnsTrue() {
        // A → B (A is blocked by B)
        let ticketA = Ticket(title: "Ticket A")
        let ticketB = Ticket(title: "Ticket B")

        // No existing deps, adding A blocked by B
        let result = engine.validateNoCycle(from: ticketA, to: ticketB, existingDeps: [:])
        XCTAssertTrue(result, "Should allow dependency when no cycle exists")
    }

    func testValidateNoCycle_selfReference_returnsFalse() {
        let ticketA = Ticket(title: "Ticket A")

        let result = engine.validateNoCycle(from: ticketA, to: ticketA, existingDeps: [:])
        XCTAssertFalse(result, "Should reject self-referencing dependency")
    }

    func testValidateNoCycle_directCycle_returnsFalse() {
        // Existing: A is blocked by B
        // Attempting: B blocked by A → would create cycle B → A → B
        let ticketA = Ticket(title: "Ticket A")
        let ticketB = Ticket(title: "Ticket B")

        ticketA.blockedBy = [ticketB]

        let existingDeps: [UUID: [Ticket]] = [ticketA.id: [ticketB]]

        // Trying to add B blocked by A
        let result = engine.validateNoCycle(from: ticketB, to: ticketA, existingDeps: existingDeps)
        XCTAssertFalse(result, "Should reject dependency that creates a direct cycle")
    }

    func testValidateNoCycle_transitiveCycle_returnsFalse() {
        // Existing: A blocked by B, B blocked by C
        // Attempting: C blocked by A → would create cycle C → A → B → C
        let ticketA = Ticket(title: "Ticket A")
        let ticketB = Ticket(title: "Ticket B")
        let ticketC = Ticket(title: "Ticket C")

        ticketA.blockedBy = [ticketB]
        ticketB.blockedBy = [ticketC]

        let existingDeps: [UUID: [Ticket]] = [
            ticketA.id: [ticketB],
            ticketB.id: [ticketC]
        ]

        // Trying to add C blocked by A
        let result = engine.validateNoCycle(from: ticketC, to: ticketA, existingDeps: existingDeps)
        XCTAssertFalse(result, "Should reject dependency that creates a transitive cycle")
    }

    func testValidateNoCycle_longChainNoCycle_returnsTrue() {
        // Existing: A blocked by B, B blocked by C, C blocked by D
        // Attempting: A blocked by D → no cycle (just adds another blocker)
        let ticketA = Ticket(title: "Ticket A")
        let ticketB = Ticket(title: "Ticket B")
        let ticketC = Ticket(title: "Ticket C")
        let ticketD = Ticket(title: "Ticket D")

        ticketA.blockedBy = [ticketB]
        ticketB.blockedBy = [ticketC]
        ticketC.blockedBy = [ticketD]

        let existingDeps: [UUID: [Ticket]] = [
            ticketA.id: [ticketB],
            ticketB.id: [ticketC],
            ticketC.id: [ticketD]
        ]

        // Trying to add A blocked by D (A already transitively depends on D, this is fine)
        let result = engine.validateNoCycle(from: ticketA, to: ticketD, existingDeps: existingDeps)
        XCTAssertTrue(result, "Should allow adding a direct dependency that already exists transitively")
    }

    func testValidateNoCycle_diamondShape_noCycle() {
        // A blocked by B, A blocked by C, B blocked by D, C blocked by D
        // Attempting: A blocked by D → no cycle
        let ticketA = Ticket(title: "Ticket A")
        let ticketB = Ticket(title: "Ticket B")
        let ticketC = Ticket(title: "Ticket C")
        let ticketD = Ticket(title: "Ticket D")

        ticketA.blockedBy = [ticketB, ticketC]
        ticketB.blockedBy = [ticketD]
        ticketC.blockedBy = [ticketD]

        let existingDeps: [UUID: [Ticket]] = [
            ticketA.id: [ticketB, ticketC],
            ticketB.id: [ticketD],
            ticketC.id: [ticketD]
        ]

        let result = engine.validateNoCycle(from: ticketA, to: ticketD, existingDeps: existingDeps)
        XCTAssertTrue(result, "Diamond-shaped dependencies should not be considered cycles")
    }

    // MARK: - Cycle Path Detection

    func testDetectCyclePath_directCycle() {
        let ticketA = Ticket(title: "Ticket A")
        let ticketB = Ticket(title: "Ticket B")

        ticketA.blockedBy = [ticketB]

        let existingDeps: [UUID: [Ticket]] = [ticketA.id: [ticketB]]

        let path = engine.detectCyclePath(from: ticketB, to: ticketA, existingDeps: existingDeps)
        XCTAssertNotNil(path, "Should detect cycle path")
        XCTAssertTrue(path!.contains("Ticket A"), "Path should contain Ticket A")
        XCTAssertTrue(path!.contains("Ticket B"), "Path should contain Ticket B")
    }

    func testDetectCyclePath_noCycle_returnsNil() {
        let ticketA = Ticket(title: "Ticket A")
        let ticketB = Ticket(title: "Ticket B")

        let path = engine.detectCyclePath(from: ticketA, to: ticketB, existingDeps: [:])
        XCTAssertNil(path, "Should return nil when no cycle exists")
    }

    // MARK: - Schedule Conflict Detection

    func testCheckScheduleConflict_dependentStartsBeforeBlockerEnds() {
        let blocker = Ticket(title: "Blocker Task")
        blocker.startDate = Date()
        blocker.endDate = Calendar.current.date(byAdding: .day, value: 5, to: Date())!

        let dependent = Ticket(title: "Dependent Task")
        dependent.startDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        dependent.endDate = Calendar.current.date(byAdding: .day, value: 8, to: Date())!

        let conflict = engine.checkScheduleConflict(dependent: dependent, blocker: blocker)
        XCTAssertNotNil(conflict, "Should detect schedule conflict when dependent starts before blocker ends")
        XCTAssertEqual(conflict?.type, .schedule)
    }

    func testCheckScheduleConflict_dependentStartsAfterBlockerEnds_noConflict() {
        let blocker = Ticket(title: "Blocker Task")
        blocker.startDate = Date()
        blocker.endDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!

        let dependent = Ticket(title: "Dependent Task")
        dependent.startDate = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        dependent.endDate = Calendar.current.date(byAdding: .day, value: 8, to: Date())!

        let conflict = engine.checkScheduleConflict(dependent: dependent, blocker: blocker)
        XCTAssertNil(conflict, "Should not detect conflict when dependent starts after blocker ends")
    }

    func testCheckScheduleConflict_noDates_noConflict() {
        let blocker = Ticket(title: "Blocker Task")
        let dependent = Ticket(title: "Dependent Task")

        let conflict = engine.checkScheduleConflict(dependent: dependent, blocker: blocker)
        XCTAssertNil(conflict, "Should not detect conflict when dates are missing")
    }

    func testCheckScheduleConflict_dependentHasNoStartDate_noConflict() {
        let blocker = Ticket(title: "Blocker Task")
        blocker.endDate = Calendar.current.date(byAdding: .day, value: 5, to: Date())!

        let dependent = Ticket(title: "Dependent Task")
        // No start date

        let conflict = engine.checkScheduleConflict(dependent: dependent, blocker: blocker)
        XCTAssertNil(conflict, "Should not detect conflict when dependent has no start date")
    }

    func testCheckScheduleConflict_blockerHasNoEndDate_noConflict() {
        let blocker = Ticket(title: "Blocker Task")
        // No end date

        let dependent = Ticket(title: "Dependent Task")
        dependent.startDate = Date()

        let conflict = engine.checkScheduleConflict(dependent: dependent, blocker: blocker)
        XCTAssertNil(conflict, "Should not detect conflict when blocker has no end date")
    }

    // MARK: - Status Conflict Detection

    func testCheckStatusConflict_dependentInProgressBlockerNotDone() {
        let blocker = Ticket(title: "Blocker Task", status: .inReview)
        let dependent = Ticket(title: "Dependent Task", status: .inProgress)

        let conflict = engine.checkStatusConflict(dependent: dependent, blocker: blocker)
        XCTAssertNotNil(conflict, "Should detect status conflict when dependent is in-progress and blocker is not done")
        XCTAssertEqual(conflict?.type, .status)
    }

    func testCheckStatusConflict_dependentInProgressBlockerDone_noConflict() {
        let blocker = Ticket(title: "Blocker Task", status: .done)
        let dependent = Ticket(title: "Dependent Task", status: .inProgress)

        let conflict = engine.checkStatusConflict(dependent: dependent, blocker: blocker)
        XCTAssertNil(conflict, "Should not detect conflict when blocker is done")
    }

    func testCheckStatusConflict_dependentNotInProgress_noConflict() {
        let blocker = Ticket(title: "Blocker Task", status: .todo)
        let dependent = Ticket(title: "Dependent Task", status: .todo)

        let conflict = engine.checkStatusConflict(dependent: dependent, blocker: blocker)
        XCTAssertNil(conflict, "Should not detect conflict when dependent is not in-progress")
    }

    func testCheckStatusConflict_dependentInProgressBlockerBacklog() {
        let blocker = Ticket(title: "Blocker Task", status: .backlog)
        let dependent = Ticket(title: "Dependent Task", status: .inProgress)

        let conflict = engine.checkStatusConflict(dependent: dependent, blocker: blocker)
        XCTAssertNotNil(conflict, "Should detect conflict when blocker is in backlog")
        XCTAssertEqual(conflict?.type, .status)
    }

    // MARK: - Workspace-Wide Evaluation

    func testEvaluateConflicts_multipleConflicts() {
        let workspace = Workspace(name: "Test Workspace")

        let blocker = Ticket(title: "Blocker", status: .todo)
        blocker.endDate = Calendar.current.date(byAdding: .day, value: 10, to: Date())!

        let dependent = Ticket(title: "Dependent", status: .inProgress)
        dependent.startDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        dependent.blockedBy = [blocker]

        blocker.workspace = workspace
        dependent.workspace = workspace
        workspace.tickets = [blocker, dependent]

        let conflicts = engine.evaluateConflicts(workspace: workspace)

        // Should have both schedule and status conflicts
        XCTAssertEqual(conflicts.count, 2, "Should detect both schedule and status conflicts")
        XCTAssertTrue(conflicts.contains(where: { $0.type == .schedule }))
        XCTAssertTrue(conflicts.contains(where: { $0.type == .status }))
    }

    func testEvaluateConflicts_noConflicts() {
        let workspace = Workspace(name: "Test Workspace")

        let blocker = Ticket(title: "Blocker", status: .done)
        blocker.endDate = Calendar.current.date(byAdding: .day, value: -2, to: Date())!

        let dependent = Ticket(title: "Dependent", status: .inProgress)
        dependent.startDate = Date()
        dependent.blockedBy = [blocker]

        blocker.workspace = workspace
        dependent.workspace = workspace
        workspace.tickets = [blocker, dependent]

        let conflicts = engine.evaluateConflicts(workspace: workspace)
        XCTAssertTrue(conflicts.isEmpty, "Should have no conflicts when blocker is done and schedule is valid")
    }

    // MARK: - Per-Ticket Evaluation

    func testEvaluateForTicket_findsRelatedConflicts() {
        let blocker = Ticket(title: "Blocker", status: .todo)
        blocker.endDate = Calendar.current.date(byAdding: .day, value: 10, to: Date())!

        let dependent = Ticket(title: "Dependent", status: .inProgress)
        dependent.startDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        dependent.blockedBy = [blocker]
        blocker.blocks = [dependent]

        let conflicts = engine.evaluateForTicket(dependent)
        XCTAssertFalse(conflicts.isEmpty, "Should find conflicts for the ticket")
    }

    func testEvaluateForTicket_checksBlocksDirection() {
        let blocker = Ticket(title: "Blocker", status: .todo)
        blocker.endDate = Calendar.current.date(byAdding: .day, value: 10, to: Date())!

        let dependent = Ticket(title: "Dependent", status: .inProgress)
        dependent.startDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        dependent.blockedBy = [blocker]
        blocker.blocks = [dependent]

        // Evaluate from the blocker's perspective
        let conflicts = engine.evaluateForTicket(blocker)
        XCTAssertFalse(conflicts.isEmpty, "Should find conflicts when evaluating from blocker side")
    }

    // MARK: - Auto-Resolution

    func testAutoResolution_conflictDisappearsWhenBlockerDone() {
        let workspace = Workspace(name: "Test Workspace")

        let blocker = Ticket(title: "Blocker", status: .todo)
        let dependent = Ticket(title: "Dependent", status: .inProgress)
        dependent.blockedBy = [blocker]

        blocker.workspace = workspace
        dependent.workspace = workspace
        workspace.tickets = [blocker, dependent]

        // Initially there's a status conflict
        var conflicts = engine.evaluateConflicts(workspace: workspace)
        XCTAssertFalse(conflicts.isEmpty, "Should have conflict initially")

        // Mark blocker as done
        blocker.status = .done

        // Re-evaluate - conflict should be resolved
        conflicts = engine.evaluateConflicts(workspace: workspace)
        let statusConflicts = conflicts.filter { $0.type == .status }
        XCTAssertTrue(statusConflicts.isEmpty, "Status conflict should be resolved when blocker is done")
    }

    func testAutoResolution_scheduleConflictDisappearsWhenRescheduled() {
        let workspace = Workspace(name: "Test Workspace")

        let blocker = Ticket(title: "Blocker")
        blocker.endDate = Calendar.current.date(byAdding: .day, value: 10, to: Date())!

        let dependent = Ticket(title: "Dependent")
        dependent.startDate = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        dependent.blockedBy = [blocker]

        blocker.workspace = workspace
        dependent.workspace = workspace
        workspace.tickets = [blocker, dependent]

        // Initially there's a schedule conflict
        var conflicts = engine.evaluateConflicts(workspace: workspace)
        XCTAssertFalse(conflicts.isEmpty, "Should have schedule conflict initially")

        // Reschedule dependent to start after blocker ends
        dependent.startDate = Calendar.current.date(byAdding: .day, value: 12, to: Date())!

        // Re-evaluate - conflict should be resolved
        conflicts = engine.evaluateConflicts(workspace: workspace)
        let scheduleConflicts = conflicts.filter { $0.type == .schedule }
        XCTAssertTrue(scheduleConflicts.isEmpty, "Schedule conflict should be resolved after rescheduling")
    }

    // MARK: - Dependency Removal Cleanup

    func testDependencyRemoval_clearsConflicts() {
        let workspace = Workspace(name: "Test Workspace")

        let blocker = Ticket(title: "Blocker", status: .todo)
        let dependent = Ticket(title: "Dependent", status: .inProgress)
        dependent.blockedBy = [blocker]
        blocker.blocks = [dependent]

        blocker.workspace = workspace
        dependent.workspace = workspace
        workspace.tickets = [blocker, dependent]

        // Initially there's a conflict
        var conflicts = engine.evaluateConflicts(workspace: workspace)
        XCTAssertFalse(conflicts.isEmpty)

        // Remove the dependency
        dependent.blockedBy.removeAll { $0.id == blocker.id }
        blocker.blocks.removeAll { $0.id == dependent.id }

        // Re-evaluate - no conflicts
        conflicts = engine.evaluateConflicts(workspace: workspace)
        XCTAssertTrue(conflicts.isEmpty, "Conflicts should be cleared after dependency removal")
    }
}
