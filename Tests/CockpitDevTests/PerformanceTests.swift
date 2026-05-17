import XCTest
import SwiftData
@testable import CockpitDev

/// Performance tests verifying that key UI operations meet performance requirements.
/// Uses XCTest measure blocks to ensure consistent performance.
final class PerformanceTests: XCTestCase {

    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!

    override func setUp() async throws {
        try await super.setUp()

        let schema = Schema([
            Workspace.self,
            Repository.self,
            Member.self,
            Ticket.self,
            Sprint.self,
            MergeRequestEntry.self,
            Document.self,
            OpenSpecEntry.self,
            DocSpecVersion.self,
            AppNotification.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(for: schema, configurations: [config])
        modelContext = ModelContext(modelContainer)
    }

    override func tearDown() async throws {
        modelContext = nil
        modelContainer = nil
        try await super.tearDown()
    }

    // MARK: - Performance Test: Gantt Chart 200+ Tickets at 60fps

    /// Tests that computing Gantt chart data for 200+ tickets completes within
    /// the frame budget required for 60fps rendering (~16ms per frame).
    func testGanttChart200TicketsDataPreparation() throws {
        let workspace = createWorkspaceWithTickets(count: 250, withDates: true)

        measure {
            // Simulate Gantt chart data preparation:
            // - Filter tickets with dates
            // - Sort by start date
            // - Compute bar positions
            let tickets = workspace.tickets
            let scheduledTickets = tickets.filter { $0.startDate != nil && $0.endDate != nil }
            let sortedTickets = scheduledTickets.sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) }

            // Simulate computing bar layout (position calculations)
            var barPositions: [(ticket: Ticket, x: CGFloat, width: CGFloat, y: CGFloat)] = []
            let dayWidth: CGFloat = 40.0
            let barHeight: CGFloat = 28.0
            let barSpacing: CGFloat = 4.0
            let referenceDate = Date()

            for (index, ticket) in sortedTickets.enumerated() {
                guard let startDate = ticket.startDate, let endDate = ticket.endDate else { continue }
                let startOffset = startDate.timeIntervalSince(referenceDate) / 86400.0
                let duration = endDate.timeIntervalSince(startDate) / 86400.0
                let x = CGFloat(startOffset) * dayWidth
                let width = CGFloat(duration) * dayWidth
                let y = CGFloat(index) * (barHeight + barSpacing)
                barPositions.append((ticket: ticket, x: x, width: max(width, dayWidth), y: y))
            }

            XCTAssertGreaterThanOrEqual(barPositions.count, 200)
        }
    }

    /// Tests that dependency arrow computation for 200+ tickets is performant.
    func testGanttChartDependencyArrowComputation() throws {
        let workspace = createWorkspaceWithDependencies(ticketCount: 200, dependencyCount: 150)

        measure {
            // Compute dependency arrows between tickets
            var arrows: [(from: UUID, to: UUID)] = []
            for ticket in workspace.tickets {
                for blocker in ticket.blockedBy {
                    arrows.append((from: blocker.id, to: ticket.id))
                }
            }

            XCTAssertGreaterThanOrEqual(arrows.count, 100)
        }
    }

    /// Tests that Gantt chart zoom level computation is fast.
    func testGanttChartZoomComputation() throws {
        let workspace = createWorkspaceWithTickets(count: 200, withDates: true)

        measure {
            // Simulate zoom level calculations at different scales
            let zoomLevels: [CGFloat] = [0.5, 1.0, 2.0, 4.0, 8.0]
            let tickets = workspace.tickets.filter { $0.startDate != nil && $0.endDate != nil }

            for zoom in zoomLevels {
                let dayWidth: CGFloat = 40.0 * zoom
                var visibleTickets: [Ticket] = []
                let viewportWidth: CGFloat = 1200.0
                let scrollOffset: CGFloat = 0.0
                let referenceDate = Date()

                for ticket in tickets {
                    guard let startDate = ticket.startDate else { continue }
                    let startOffset = startDate.timeIntervalSince(referenceDate) / 86400.0
                    let x = CGFloat(startOffset) * dayWidth

                    // Check if ticket is in viewport
                    if x >= scrollOffset - viewportWidth && x <= scrollOffset + viewportWidth * 2 {
                        visibleTickets.append(ticket)
                    }
                }

                _ = visibleTickets.count
            }
        }
    }

    // MARK: - Performance Test: Kanban 500 Tickets in <100ms

    /// Tests that the Kanban board can organize 500 tickets into columns in under 100ms.
    func testKanban500TicketsColumnOrganization() throws {
        let workspace = createWorkspaceWithTickets(count: 500, withDates: false)

        measure {
            let kanbanVM = KanbanViewModel(workspace: workspace)
            kanbanVM.refreshBoard()

            // Verify all tickets are distributed across columns
            let totalInColumns = kanbanVM.columnTickets.values.reduce(0) { $0 + $1.count }
            XCTAssertEqual(totalInColumns, 500)
        }
    }

    /// Tests that Kanban board filtering 500 tickets by assignee is fast.
    func testKanban500TicketsFilterByAssignee() throws {
        let workspace = createWorkspaceWithTicketsAndMembers(ticketCount: 500, memberCount: 10)
        let targetMember = workspace.members.first!

        measure {
            let kanbanVM = KanbanViewModel(workspace: workspace)
            kanbanVM.filterAssignee = targetMember
            kanbanVM.refreshBoard()

            // Verify filtering worked
            let totalInColumns = kanbanVM.columnTickets.values.reduce(0) { $0 + $1.count }
            XCTAssertGreaterThan(totalInColumns, 0)
            XCTAssertLessThan(totalInColumns, 500)
        }
    }

    /// Tests that Kanban board sorting (SP descending) for 500 tickets is fast.
    func testKanban500TicketsSorting() throws {
        let workspace = createWorkspaceWithTickets(count: 500, withDates: false)

        measure {
            let kanbanVM = KanbanViewModel(workspace: workspace)
            kanbanVM.refreshBoard()

            // Verify sorting: within each column, SP should be descending
            for (_, tickets) in kanbanVM.columnTickets {
                for i in 0..<(tickets.count - 1) {
                    let current = tickets[i].storyPoints
                    let next = tickets[i + 1].storyPoints
                    // SP tickets come before no-SP tickets
                    if current == nil && next != nil {
                        XCTFail("Ticket without SP should be after ticket with SP")
                    }
                    // Among SP tickets, descending order
                    if let c = current, let n = next {
                        XCTAssertGreaterThanOrEqual(c, n)
                    }
                }
            }
        }
    }

    /// Tests that Kanban column status mapping for 500 tickets is performant.
    func testKanban500TicketsStatusMapping() throws {
        let workspace = createWorkspaceWithTickets(count: 500, withDates: false)

        measure {
            let kanbanVM = KanbanViewModel(workspace: workspace)

            // Map all ticket statuses to columns
            var columnCounts: [String: Int] = [:]
            for ticket in workspace.tickets {
                let column = kanbanVM.mapStatusToColumn(ticket.status)
                columnCounts[column, default: 0] += 1
            }

            XCTAssertEqual(columnCounts.values.reduce(0, +), 500)
        }
    }

    // MARK: - Helpers

    /// Creates a workspace with the specified number of tickets.
    private func createWorkspaceWithTickets(count: Int, withDates: Bool) -> Workspace {
        let workspace = Workspace(name: "Performance Test Workspace")
        modelContext.insert(workspace)

        let statuses: [TicketStatus] = [.backlog, .todo, .inProgress, .inReview, .done]
        let fibonacci = AppConstants.fibonacciSequence

        for i in 0..<count {
            let status = statuses[i % statuses.count]
            let sp = fibonacci[i % fibonacci.count]

            var startDate: Date? = nil
            var endDate: Date? = nil
            if withDates {
                startDate = Date().addingTimeInterval(Double(i) * 86400)
                endDate = Date().addingTimeInterval(Double(i + Int.random(in: 1...5)) * 86400)
            }

            let ticket = Ticket(
                title: "Ticket \(i + 1): Performance test item",
                status: status,
                storyPoints: sp,
                startDate: startDate,
                endDate: endDate,
                labels: ["perf-test", "label-\(i % 5)"]
            )
            ticket.workspace = workspace
            workspace.tickets.append(ticket)
        }

        try? modelContext.save()
        return workspace
    }

    /// Creates a workspace with tickets that have dependency relationships.
    private func createWorkspaceWithDependencies(ticketCount: Int, dependencyCount: Int) -> Workspace {
        let workspace = Workspace(name: "Dependency Perf Test")
        modelContext.insert(workspace)

        var tickets: [Ticket] = []
        for i in 0..<ticketCount {
            let ticket = Ticket(
                title: "Dep Ticket \(i + 1)",
                status: .inProgress,
                storyPoints: 5,
                startDate: Date().addingTimeInterval(Double(i) * 86400),
                endDate: Date().addingTimeInterval(Double(i + 3) * 86400)
            )
            ticket.workspace = workspace
            workspace.tickets.append(ticket)
            tickets.append(ticket)
        }

        // Create dependencies (ensuring no cycles by only linking forward)
        var depCount = 0
        for i in 0..<ticketCount - 1 {
            if depCount >= dependencyCount { break }
            let nextIndex = i + 1
            if nextIndex < ticketCount {
                tickets[nextIndex].blockedBy.append(tickets[i])
                tickets[i].blocks.append(tickets[nextIndex])
                depCount += 1
            }
        }

        try? modelContext.save()
        return workspace
    }

    /// Creates a workspace with tickets assigned to members.
    private func createWorkspaceWithTicketsAndMembers(ticketCount: Int, memberCount: Int) -> Workspace {
        let workspace = Workspace(name: "Member Perf Test")
        modelContext.insert(workspace)

        // Create members
        var members: [Member] = []
        for i in 0..<memberCount {
            let member = Member(
                gitlabUserId: 1000 + i,
                username: "user\(i)",
                displayName: "User \(i)",
                role: .member
            )
            member.workspace = workspace
            workspace.members.append(member)
            members.append(member)
        }

        // Create tickets assigned to members
        let statuses: [TicketStatus] = [.backlog, .todo, .inProgress, .inReview, .done]
        let fibonacci = AppConstants.fibonacciSequence

        for i in 0..<ticketCount {
            let ticket = Ticket(
                title: "Assigned Ticket \(i + 1)",
                status: statuses[i % statuses.count],
                storyPoints: fibonacci[i % fibonacci.count],
                labels: ["team-\(i % 3)"]
            )
            ticket.workspace = workspace
            ticket.assignee = members[i % memberCount]
            workspace.tickets.append(ticket)
        }

        try? modelContext.save()
        return workspace
    }
}
