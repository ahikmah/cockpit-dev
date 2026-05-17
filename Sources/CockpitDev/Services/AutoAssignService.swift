import Foundation

// MARK: - Assignment Suggestion

/// Represents a suggested ticket assignment from the auto-assign algorithm.
struct AssignmentSuggestion: Identifiable {
    let id: UUID
    let ticket: Ticket
    let suggestedMember: Member?
    let resultingWorkload: Int
    let reason: String?

    init(ticket: Ticket, suggestedMember: Member?, resultingWorkload: Int, reason: String? = nil) {
        self.id = UUID()
        self.ticket = ticket
        self.suggestedMember = suggestedMember
        self.resultingWorkload = resultingWorkload
        self.reason = reason
    }
}

// MARK: - AutoAssignService

/// Service responsible for automatically suggesting ticket assignments based on
/// developer skill profiles and current workload.
///
/// The algorithm:
/// 1. Classifies each ticket as backend, frontend, or fullstack
/// 2. Sorts tickets by complexity (story points) descending
/// 3. For each ticket, scores eligible members using:
///    (skill fit score × 10) + (max threshold - current assigned SP)
/// 4. Assigns the highest-scoring member
/// 5. Excludes members at/above the workload threshold
/// 6. Skips tickets without story points
/// 7. Reports unassignable tickets with reasons
class AutoAssignService {

    // MARK: - Keyword Sets for Classification

    /// Keywords indicating backend-heavy work.
    static let backendKeywords: Set<String> = [
        "api", "backend", "server", "database", "db", "migration",
        "endpoint", "rest", "graphql", "microservice", "service",
        "authentication", "auth", "security", "infrastructure",
        "devops", "ci/cd", "pipeline", "deploy", "docker",
        "kubernetes", "k8s", "redis", "postgres", "mysql",
        "mongodb", "queue", "worker", "cron", "scheduler"
    ]

    /// Keywords indicating frontend-heavy work.
    static let frontendKeywords: Set<String> = [
        "ui", "frontend", "front-end", "design", "css", "html",
        "component", "layout", "responsive", "animation", "ux",
        "accessibility", "a11y", "style", "theme", "icon",
        "button", "form", "modal", "navigation", "menu",
        "dashboard", "chart", "visualization", "swiftui", "view"
    ]

    // MARK: - Ticket Classification

    /// Classifies a ticket as backend-heavy, frontend-heavy, or fullstack
    /// based on its labels and description keywords.
    ///
    /// Classification logic:
    /// 1. Check labels for backend/frontend keywords
    /// 2. Check description for backend/frontend keywords
    /// 3. If both or neither match, classify as fullstack
    ///
    /// - Parameter ticket: The ticket to classify.
    /// - Returns: The skill profile classification for the ticket.
    func classifyTicket(_ ticket: Ticket) -> SkillProfile {
        var backendScore = 0
        var frontendScore = 0

        // Check labels
        for label in ticket.labels {
            let lowercased = label.lowercased()
            if Self.backendKeywords.contains(lowercased) {
                backendScore += 2
            }
            if Self.frontendKeywords.contains(lowercased) {
                frontendScore += 2
            }
        }

        // Check description keywords
        if let description = ticket.descriptionText?.lowercased() {
            let words = description.split(separator: " ").map { String($0) }
            for word in words {
                let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
                if Self.backendKeywords.contains(cleaned) {
                    backendScore += 1
                }
                if Self.frontendKeywords.contains(cleaned) {
                    frontendScore += 1
                }
            }
        }

        // Check title keywords as well
        let titleWords = ticket.title.lowercased().split(separator: " ").map { String($0) }
        for word in titleWords {
            let cleaned = word.trimmingCharacters(in: .punctuationCharacters)
            if Self.backendKeywords.contains(cleaned) {
                backendScore += 1
            }
            if Self.frontendKeywords.contains(cleaned) {
                frontendScore += 1
            }
        }

        // Determine classification
        if backendScore > frontendScore {
            return .beHeavy
        } else if frontendScore > backendScore {
            return .feHeavy
        } else {
            return .fullstack
        }
    }

    // MARK: - Skill Fit Scoring

    /// Calculates the skill fit score between a member and a ticket type.
    ///
    /// Scoring:
    /// - 10: Exact match (member's skill profile matches ticket classification)
    /// - 5: Fullstack member (can handle any ticket type)
    /// - 0: Mismatch (member's skill doesn't match ticket type)
    ///
    /// - Parameters:
    ///   - member: The member to score.
    ///   - ticketType: The ticket's skill classification.
    /// - Returns: The skill fit score (0, 5, or 10).
    func skillFitScore(member: Member, ticketType: SkillProfile) -> Int {
        guard let memberSkill = member.skillProfile else {
            return 0
        }

        if memberSkill == ticketType {
            return 10
        } else if memberSkill == .fullstack {
            return 5
        } else {
            return 0
        }
    }

    // MARK: - Compute Assignments

    /// Computes assignment suggestions for a set of tickets using a greedy algorithm.
    ///
    /// Algorithm:
    /// 1. Filter out tickets without story points (skipped with reason)
    /// 2. Sort remaining tickets by story points descending (complexity first)
    /// 3. For each ticket:
    ///    a. Classify the ticket type
    ///    b. Score each eligible member: (skill fit × 10) + (threshold - current SP)
    ///    c. Exclude members at/above the threshold
    ///    d. Assign the highest-scoring member
    ///    e. Update the member's running workload
    /// 4. Report unassignable tickets with reasons
    ///
    /// - Parameters:
    ///   - tickets: The tickets to assign.
    ///   - members: The available team members.
    ///   - sprint: The sprint context for workload calculation.
    ///   - maxThreshold: The maximum story points threshold per member.
    /// - Returns: An array of assignment suggestions.
    func computeAssignments(
        tickets: [Ticket],
        members: [Member],
        sprint: Sprint,
        maxThreshold: Int
    ) -> [AssignmentSuggestion] {
        var suggestions: [AssignmentSuggestion] = []

        // Calculate current workload per member from sprint tickets
        var memberWorkload: [UUID: Int] = [:]
        for member in members {
            let assignedSP = sprint.tickets
                .filter { $0.assignee?.id == member.id }
                .compactMap { $0.storyPoints }
                .reduce(0, +)
            memberWorkload[member.id] = assignedSP
        }

        // Separate tickets: those with SP and those without
        var ticketsWithSP: [Ticket] = []
        var ticketsWithoutSP: [Ticket] = []

        for ticket in tickets {
            if ticket.storyPoints != nil {
                ticketsWithSP.append(ticket)
            } else {
                ticketsWithoutSP.append(ticket)
            }
        }

        // Skip tickets without story points
        for ticket in ticketsWithoutSP {
            suggestions.append(AssignmentSuggestion(
                ticket: ticket,
                suggestedMember: nil,
                resultingWorkload: 0,
                reason: "Skipped: Story points are required for auto-assign"
            ))
        }

        // Sort tickets by complexity descending (higher SP first)
        ticketsWithSP.sort { ($0.storyPoints ?? 0) > ($1.storyPoints ?? 0) }

        // Greedy assignment
        for ticket in ticketsWithSP {
            let ticketType = classifyTicket(ticket)
            let ticketSP = ticket.storyPoints ?? 0

            // Score each eligible member
            var bestMember: Member?
            var bestScore = Int.min
            var bestResultingWorkload = 0

            for member in members {
                let currentWorkload = memberWorkload[member.id] ?? 0

                // Exclude members at or above threshold
                if currentWorkload >= maxThreshold {
                    continue
                }

                let fitScore = skillFitScore(member: member, ticketType: ticketType)

                // Skip members with zero skill fit (mismatch)
                if fitScore == 0 {
                    continue
                }

                let score = (fitScore * 10) + (maxThreshold - currentWorkload)

                if score > bestScore {
                    bestScore = score
                    bestMember = member
                    bestResultingWorkload = currentWorkload + ticketSP
                }
            }

            if let assignedMember = bestMember {
                // Update running workload
                memberWorkload[assignedMember.id] = bestResultingWorkload

                suggestions.append(AssignmentSuggestion(
                    ticket: ticket,
                    suggestedMember: assignedMember,
                    resultingWorkload: bestResultingWorkload,
                    reason: nil
                ))
            } else {
                // No eligible member found - determine reason
                let reason = determineUnassignableReason(
                    ticket: ticket,
                    ticketType: ticketType,
                    members: members,
                    memberWorkload: memberWorkload,
                    maxThreshold: maxThreshold
                )

                suggestions.append(AssignmentSuggestion(
                    ticket: ticket,
                    suggestedMember: nil,
                    resultingWorkload: 0,
                    reason: reason
                ))
            }
        }

        return suggestions
    }

    // MARK: - Private Helpers

    /// Determines the reason why a ticket cannot be assigned.
    private func determineUnassignableReason(
        ticket: Ticket,
        ticketType: SkillProfile,
        members: [Member],
        memberWorkload: [UUID: Int],
        maxThreshold: Int
    ) -> String {
        let membersWithMatchingSkill = members.filter { member in
            skillFitScore(member: member, ticketType: ticketType) > 0
        }

        if membersWithMatchingSkill.isEmpty {
            let typeDescription: String
            switch ticketType {
            case .beHeavy:
                typeDescription = "backend"
            case .feHeavy:
                typeDescription = "frontend"
            case .fullstack:
                typeDescription = "fullstack"
            }
            return "No member with matching skill profile (\(typeDescription)) available"
        }

        let allAtThreshold = membersWithMatchingSkill.allSatisfy { member in
            (memberWorkload[member.id] ?? 0) >= maxThreshold
        }

        if allAtThreshold {
            return "All eligible members have reached the workload threshold (\(maxThreshold) SP)"
        }

        return "No eligible member available for assignment"
    }
}
