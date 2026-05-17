import Foundation

// MARK: - Webhook Event Types

/// Represents a parsed webhook event from GitLab.
enum WebhookEvent: Equatable {
    case issueHook(IssueWebhookPayload)
    case mergeRequestHook(MRWebhookPayload)
    case pushHook(PushWebhookPayload)
    case pipelineHook(PipelineWebhookPayload)
}

// MARK: - Issue Webhook Payload

/// Payload for GitLab Issue Hook events.
struct IssueWebhookPayload: Codable, Equatable {
    let objectKind: String
    let eventType: String
    let objectAttributes: IssueAttributes
    let project: WebhookProject

    enum CodingKeys: String, CodingKey {
        case objectKind = "object_kind"
        case eventType = "event_type"
        case objectAttributes = "object_attributes"
        case project
    }

    struct IssueAttributes: Codable, Equatable {
        let id: Int
        let iid: Int
        let title: String
        let description: String?
        let state: String
        let action: String
        let weight: Int?
        let labels: [WebhookLabel]?
        let updatedAt: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, iid, title, description, state, action, weight, labels
            case updatedAt = "updated_at"
            case createdAt = "created_at"
        }
    }
}

// MARK: - Merge Request Webhook Payload

/// Payload for GitLab Merge Request Hook events.
struct MRWebhookPayload: Codable, Equatable {
    let objectKind: String
    let eventType: String
    let objectAttributes: MRAttributes
    let project: WebhookProject

    enum CodingKeys: String, CodingKey {
        case objectKind = "object_kind"
        case eventType = "event_type"
        case objectAttributes = "object_attributes"
        case project
    }

    struct MRAttributes: Codable, Equatable {
        let id: Int
        let iid: Int
        let title: String
        let description: String?
        let state: String
        let action: String
        let sourceBranch: String
        let targetBranch: String
        let authorId: Int
        let updatedAt: String
        let createdAt: String

        enum CodingKeys: String, CodingKey {
            case id, iid, title, description, state, action
            case sourceBranch = "source_branch"
            case targetBranch = "target_branch"
            case authorId = "author_id"
            case updatedAt = "updated_at"
            case createdAt = "created_at"
        }
    }
}

// MARK: - Push Webhook Payload

/// Payload for GitLab Push Hook events.
struct PushWebhookPayload: Codable, Equatable {
    let objectKind: String
    let eventName: String
    let ref: String
    let before: String
    let after: String
    let projectId: Int
    let project: WebhookProject
    let commits: [WebhookCommit]?
    let totalCommitsCount: Int

    enum CodingKeys: String, CodingKey {
        case objectKind = "object_kind"
        case eventName = "event_name"
        case ref, before, after
        case projectId = "project_id"
        case project, commits
        case totalCommitsCount = "total_commits_count"
    }

    /// Extracts the branch name from the ref (e.g., "refs/heads/main" → "main").
    var branchName: String {
        let prefix = "refs/heads/"
        if ref.hasPrefix(prefix) {
            return String(ref.dropFirst(prefix.count))
        }
        return ref
    }

    /// Whether this push represents a branch deletion (after is all zeros).
    var isBranchDeletion: Bool {
        after == "0000000000000000000000000000000000000000"
    }

    /// Whether this push represents a new branch creation (before is all zeros).
    var isBranchCreation: Bool {
        before == "0000000000000000000000000000000000000000"
    }
}

// MARK: - Pipeline Webhook Payload

/// Payload for GitLab Pipeline Hook events.
struct PipelineWebhookPayload: Codable, Equatable {
    let objectKind: String
    let objectAttributes: PipelineAttributes
    let project: WebhookProject
    let mergeRequest: PipelineMR?

    enum CodingKeys: String, CodingKey {
        case objectKind = "object_kind"
        case objectAttributes = "object_attributes"
        case project
        case mergeRequest = "merge_request"
    }

    struct PipelineAttributes: Codable, Equatable {
        let id: Int
        let ref: String
        let status: String
        let sha: String
        let source: String?
        let createdAt: String
        let finishedAt: String?

        enum CodingKeys: String, CodingKey {
            case id, ref, status, sha, source
            case createdAt = "created_at"
            case finishedAt = "finished_at"
        }
    }

    struct PipelineMR: Codable, Equatable {
        let id: Int
        let iid: Int
        let title: String
        let sourceBranch: String
        let targetBranch: String

        enum CodingKeys: String, CodingKey {
            case id, iid, title
            case sourceBranch = "source_branch"
            case targetBranch = "target_branch"
        }
    }
}

// MARK: - Shared Webhook Types

/// Represents a project in webhook payloads.
struct WebhookProject: Codable, Equatable {
    let id: Int
    let name: String
    let webUrl: String
    let pathWithNamespace: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case webUrl = "web_url"
        case pathWithNamespace = "path_with_namespace"
    }
}

/// Represents a label in webhook payloads.
struct WebhookLabel: Codable, Equatable {
    let id: Int
    let title: String
    let color: String?
}

/// Represents a commit in push webhook payloads.
struct WebhookCommit: Codable, Equatable {
    let id: String
    let message: String
    let timestamp: String
    let url: String
    let author: WebhookCommitAuthor
    let added: [String]?
    let modified: [String]?
    let removed: [String]?
}

/// Represents a commit author in webhook payloads.
struct WebhookCommitAuthor: Codable, Equatable {
    let name: String
    let email: String
}

// MARK: - Webhook Errors

/// Errors that can occur during webhook processing.
enum WebhookError: Error, LocalizedError {
    case portBindingFailed(port: Int)
    case allPortsExhausted
    case invalidToken
    case malformedPayload(reason: String)
    case unknownEventType(String)
    case serverAlreadyRunning
    case serverNotRunning
    case connectionError(Error)

    var errorDescription: String? {
        switch self {
        case .portBindingFailed(let port):
            return "Failed to bind to port \(port)"
        case .allPortsExhausted:
            return "All webhook ports (9876-9886) are in use. Falling back to polling-only mode."
        case .invalidToken:
            return "Invalid webhook token"
        case .malformedPayload(let reason):
            return "Malformed webhook payload: \(reason)"
        case .unknownEventType(let type):
            return "Unknown webhook event type: \(type)"
        case .serverAlreadyRunning:
            return "Webhook server is already running"
        case .serverNotRunning:
            return "Webhook server is not running"
        case .connectionError(let error):
            return "Connection error: \(error.localizedDescription)"
        }
    }
}
