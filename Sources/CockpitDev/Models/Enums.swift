import Foundation

// MARK: - Member Role

/// Defines the permission level assigned to a Member within a Workspace.
enum MemberRole: String, Codable, CaseIterable {
    case owner
    case admin
    case member
    case viewer
}

// MARK: - Skill Profile

/// Classification of a Member's expertise used for Auto-Assign.
enum SkillProfile: String, Codable, CaseIterable {
    case beHeavy
    case feHeavy
    case fullstack
}

// MARK: - Ticket Status

/// Represents the workflow status of a Ticket on the Kanban board.
enum TicketStatus: String, Codable, CaseIterable {
    case backlog
    case todo
    case inProgress
    case inReview
    case done
}

// MARK: - Ticket Priority

/// Priority level for a Ticket.
enum TicketPriority: String, Codable, CaseIterable {
    case critical
    case high
    case medium
    case low
}

// MARK: - Pipeline Status

/// Status of a GitLab CI/CD pipeline.
enum PipelineStatus: String, Codable, CaseIterable {
    case running
    case success
    case failed
    case canceled
    case pending
}

// MARK: - Merge Request State

/// State of a GitLab Merge Request.
enum MRState: String, Codable, CaseIterable {
    case opened
    case merged
    case closed
}

// MARK: - Spec Phase

/// Phase of an OpenSpec specification document.
enum SpecPhase: String, Codable, CaseIterable {
    case proposal
    case design
    case tasks
}

// MARK: - Notification Event Type

/// Types of events that can trigger notifications.
enum NotificationEventType: String, Codable, CaseIterable {
    case newMergeRequest
    case mrApproval
    case dependencyConflict
    case sprintCompletion
}
