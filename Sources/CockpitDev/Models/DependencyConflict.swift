import Foundation

/// Represents a conflict detected between dependent tickets.
/// Conflicts arise from scheduling issues or status inconsistencies.
struct DependencyConflict: Identifiable, Equatable {
    let id: UUID
    let type: ConflictType
    let dependentTicket: Ticket
    let blockerTicket: Ticket
    let description: String

    /// The type of dependency conflict.
    enum ConflictType: String, Equatable {
        case schedule
        case status
    }

    init(
        id: UUID = UUID(),
        type: ConflictType,
        dependentTicket: Ticket,
        blockerTicket: Ticket,
        description: String
    ) {
        self.id = id
        self.type = type
        self.dependentTicket = dependentTicket
        self.blockerTicket = blockerTicket
        self.description = description
    }

    static func == (lhs: DependencyConflict, rhs: DependencyConflict) -> Bool {
        lhs.id == rhs.id
    }
}
