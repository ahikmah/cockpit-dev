import Foundation

/// Engine responsible for validating dependency relationships and detecting conflicts.
///
/// Key responsibilities:
/// - Circular dependency validation via DFS traversal (DAG enforcement)
/// - Schedule conflict detection (dependent starts before blocker ends)
/// - Status conflict detection (dependent in-progress while blocker not done)
/// - Workspace-wide conflict evaluation
/// - Per-ticket conflict evaluation within 5 seconds
class DependencyConflictEngine {

    // MARK: - Circular Dependency Validation

    /// Validates that adding a dependency from `from` (dependent) to `to` (blocker)
    /// does not create a circular chain.
    ///
    /// Uses DFS traversal starting from `to` following existing dependencies
    /// to check if `from` is reachable (which would create a cycle).
    ///
    /// - Parameters:
    ///   - from: The dependent ticket (the one being blocked).
    ///   - to: The blocker ticket (the one that blocks).
    ///   - existingDeps: The current dependency graph mapping each ticket to its blockers.
    /// - Returns: `true` if no cycle would be created, `false` if a cycle is detected.
    func validateNoCycle(from: Ticket, to: Ticket, existingDeps: [UUID: [Ticket]]) -> Bool {
        // If from == to, it's a self-reference cycle
        if from.id == to.id {
            return false
        }

        // DFS from `to` following its blockers to see if we can reach `from`
        var visited: Set<UUID> = []
        return !canReach(from: to, target: from, existingDeps: existingDeps, visited: &visited)
    }

    /// Detects the circular path if adding a dependency from `from` to `to` would create a cycle.
    ///
    /// - Parameters:
    ///   - from: The dependent ticket.
    ///   - to: The blocker ticket.
    ///   - existingDeps: The current dependency graph.
    /// - Returns: An array of ticket titles representing the cycle path, or nil if no cycle.
    func detectCyclePath(from: Ticket, to: Ticket, existingDeps: [UUID: [Ticket]]) -> [String]? {
        if from.id == to.id {
            return [from.title, from.title]
        }

        var path: [String] = [from.title, to.title]
        var visited: Set<UUID> = [from.id, to.id]

        if findCyclePath(current: to, target: from, existingDeps: existingDeps, visited: &visited, path: &path) {
            return path
        }

        return nil
    }

    // MARK: - Conflict Evaluation

    /// Evaluates all dependency conflicts within a workspace.
    ///
    /// Iterates through all tickets and their dependencies to find schedule and status conflicts.
    ///
    /// - Parameter workspace: The workspace to evaluate.
    /// - Returns: An array of all active dependency conflicts.
    func evaluateConflicts(workspace: Workspace) -> [DependencyConflict] {
        var conflicts: [DependencyConflict] = []

        for ticket in workspace.tickets {
            // Check conflicts where this ticket is the dependent (blocked by others)
            for blocker in ticket.blockedBy {
                if let conflict = checkScheduleConflict(dependent: ticket, blocker: blocker) {
                    conflicts.append(conflict)
                }
                if let conflict = checkStatusConflict(dependent: ticket, blocker: blocker) {
                    conflicts.append(conflict)
                }
            }
        }

        return conflicts
    }

    /// Evaluates conflicts for a specific ticket and all its related dependencies.
    ///
    /// Checks both direct and transitive dependencies for conflicts.
    /// Designed to complete within 5 seconds.
    ///
    /// - Parameter ticket: The ticket to evaluate.
    /// - Returns: An array of conflicts related to this ticket.
    func evaluateForTicket(_ ticket: Ticket) -> [DependencyConflict] {
        var conflicts: [DependencyConflict] = []
        var visited: Set<UUID> = []

        // Check conflicts where this ticket is the dependent
        evaluateTransitiveDependencies(
            ticket: ticket,
            direction: .blockedBy,
            conflicts: &conflicts,
            visited: &visited
        )

        // Reset visited for the other direction
        visited.removeAll()

        // Check conflicts where this ticket is the blocker
        evaluateTransitiveDependencies(
            ticket: ticket,
            direction: .blocks,
            conflicts: &conflicts,
            visited: &visited
        )

        return conflicts
    }

    // MARK: - Individual Conflict Checks

    /// Checks for a schedule conflict between a dependent ticket and its blocker.
    ///
    /// A schedule conflict exists when the dependent ticket's start date is before
    /// the blocker ticket's end date (the dependent is scheduled to start before
    /// the blocker finishes).
    ///
    /// - Parameters:
    ///   - dependent: The ticket that is blocked.
    ///   - blocker: The ticket that blocks.
    /// - Returns: A `DependencyConflict` if a schedule conflict exists, or `nil`.
    func checkScheduleConflict(dependent: Ticket, blocker: Ticket) -> DependencyConflict? {
        guard let dependentStart = dependent.startDate,
              let blockerEnd = blocker.endDate else {
            return nil
        }

        // Conflict: dependent starts before blocker ends
        if dependentStart < blockerEnd {
            return DependencyConflict(
                type: .schedule,
                dependentTicket: dependent,
                blockerTicket: blocker,
                description: "\"\(dependent.title)\" is scheduled to start before \"\(blocker.title)\" ends."
            )
        }

        return nil
    }

    /// Checks for a status conflict between a dependent ticket and its blocker.
    ///
    /// A status conflict exists when the dependent ticket is "in progress"
    /// while the blocker ticket is not "done".
    ///
    /// - Parameters:
    ///   - dependent: The ticket that is blocked.
    ///   - blocker: The ticket that blocks.
    /// - Returns: A `DependencyConflict` if a status conflict exists, or `nil`.
    func checkStatusConflict(dependent: Ticket, blocker: Ticket) -> DependencyConflict? {
        // Conflict: dependent is in-progress but blocker is not done
        if dependent.status == .inProgress && blocker.status != .done {
            return DependencyConflict(
                type: .status,
                dependentTicket: dependent,
                blockerTicket: blocker,
                description: "\"\(dependent.title)\" is in progress, but blocker \"\(blocker.title)\" is not done (status: \(blocker.status.rawValue))."
            )
        }

        return nil
    }

    // MARK: - Private Helpers

    private enum DependencyDirection {
        case blockedBy
        case blocks
    }

    /// Recursively evaluates transitive dependencies for conflicts.
    private func evaluateTransitiveDependencies(
        ticket: Ticket,
        direction: DependencyDirection,
        conflicts: inout [DependencyConflict],
        visited: inout Set<UUID>
    ) {
        guard !visited.contains(ticket.id) else { return }
        visited.insert(ticket.id)

        switch direction {
        case .blockedBy:
            // This ticket is dependent on its blockers
            for blocker in ticket.blockedBy {
                if let conflict = checkScheduleConflict(dependent: ticket, blocker: blocker) {
                    if !conflicts.contains(where: { $0.dependentTicket.id == ticket.id && $0.blockerTicket.id == blocker.id && $0.type == .schedule }) {
                        conflicts.append(conflict)
                    }
                }
                if let conflict = checkStatusConflict(dependent: ticket, blocker: blocker) {
                    if !conflicts.contains(where: { $0.dependentTicket.id == ticket.id && $0.blockerTicket.id == blocker.id && $0.type == .status }) {
                        conflicts.append(conflict)
                    }
                }
                // Recurse into blocker's blockers
                evaluateTransitiveDependencies(ticket: blocker, direction: .blockedBy, conflicts: &conflicts, visited: &visited)
            }

        case .blocks:
            // This ticket blocks others
            for dependent in ticket.blocks {
                if let conflict = checkScheduleConflict(dependent: dependent, blocker: ticket) {
                    if !conflicts.contains(where: { $0.dependentTicket.id == dependent.id && $0.blockerTicket.id == ticket.id && $0.type == .schedule }) {
                        conflicts.append(conflict)
                    }
                }
                if let conflict = checkStatusConflict(dependent: dependent, blocker: ticket) {
                    if !conflicts.contains(where: { $0.dependentTicket.id == dependent.id && $0.blockerTicket.id == ticket.id && $0.type == .status }) {
                        conflicts.append(conflict)
                    }
                }
                // Recurse into dependent's dependents
                evaluateTransitiveDependencies(ticket: dependent, direction: .blocks, conflicts: &conflicts, visited: &visited)
            }
        }
    }

    /// DFS to check if `target` is reachable from `current` following blockedBy edges.
    private func canReach(from current: Ticket, target: Ticket, existingDeps: [UUID: [Ticket]], visited: inout Set<UUID>) -> Bool {
        guard !visited.contains(current.id) else { return false }
        visited.insert(current.id)

        let blockers = existingDeps[current.id] ?? current.blockedBy
        for blocker in blockers {
            if blocker.id == target.id {
                return true
            }
            if canReach(from: blocker, target: target, existingDeps: existingDeps, visited: &visited) {
                return true
            }
        }

        return false
    }

    /// DFS to find the cycle path from `current` back to `target`.
    private func findCyclePath(current: Ticket, target: Ticket, existingDeps: [UUID: [Ticket]], visited: inout Set<UUID>, path: inout [String]) -> Bool {
        let blockers = existingDeps[current.id] ?? current.blockedBy
        for blocker in blockers {
            if blocker.id == target.id {
                path.append(target.title)
                return true
            }
            if !visited.contains(blocker.id) {
                visited.insert(blocker.id)
                path.append(blocker.title)
                if findCyclePath(current: blocker, target: target, existingDeps: existingDeps, visited: &visited, path: &path) {
                    return true
                }
                path.removeLast()
            }
        }
        return false
    }
}
