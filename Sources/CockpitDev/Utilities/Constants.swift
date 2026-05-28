import Foundation

/// App-wide constants for Cockpit Dev.
enum AppConstants {

    // MARK: - Webhook Server

    /// Default port for the local webhook server.
    static let defaultWebhookPort: Int = 9876

    /// Range of fallback ports to try if the default port is occupied.
    static let webhookPortRange: ClosedRange<Int> = 9876...9886

    // MARK: - Notifications

    /// Maximum number of notification entries retained per workspace.
    static let maxNotifications: Int = 500

    // MARK: - Sync

    /// Default polling interval in seconds for GitLab reconciliation.
    static let defaultPollInterval: TimeInterval = 300

    // MARK: - Story Points

    /// Allowed Fibonacci sequence values for story point estimation.
    static let fibonacciSequence: [Int] = [1, 2, 3, 5, 8, 13, 21]

    /// Maximum story points threshold for workload distribution (default).
    static let maxStoryPointsThreshold: Int = 21

    // MARK: - Validation

    /// Maximum length for a workspace name.
    static let maxWorkspaceNameLength: Int = 100

    /// Maximum length for a commit message.
    static let maxCommitMessageLength: Int = 500

    /// Maximum file size in bytes (100 MB).
    static let maxFileSizeBytes: Int64 = 100 * 1024 * 1024

    // MARK: - GitLab API

    /// Default GitLab instance URL.
    static let defaultGitLabInstanceURL: String = "https://gitlab.com"

    /// OpenSpec PM API that owns timeline planning metadata.
    static let openSpecPMInstanceURL: String = "https://ospm.devyard.space"

    /// Maximum retry attempts for API requests.
    static let maxRetryAttempts: Int = 3

    /// Retry delays in seconds (exponential backoff).
    static let retryDelays: [TimeInterval] = [1.0, 2.0, 4.0]

    // MARK: - AI Service

    /// Default timeout for AI API requests in seconds.
    static let defaultAITimeout: TimeInterval = 120

    // MARK: - Authentication

    /// Maximum consecutive authentication failures before lockout.
    static let maxAuthFailures: Int = 5

    /// Lockout duration in seconds after max auth failures.
    static let authLockoutDuration: TimeInterval = 60

    // MARK: - UI

    /// Maximum number of Kanban columns allowed.
    static let maxKanbanColumns: Int = 10

    /// Maximum characters for ticket title display on Kanban cards.
    static let maxTicketTitleDisplayLength: Int = 80

    /// Maximum search results for GitLab user search.
    static let maxUserSearchResults: Int = 20

    /// Default Kanban column names.
    static let defaultKanbanColumns: [String] = [
        "Backlog", "To Do", "In Progress", "In Review", "Done"
    ]
}
