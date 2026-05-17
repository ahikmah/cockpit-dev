import Foundation

// MARK: - Git Credentials

/// Credentials used for authenticating Git operations.
struct GitCredentials: Sendable {
    /// The OAuth token used for HTTPS authentication.
    let oauthToken: String
    /// The username for authentication (typically "oauth2" for GitLab OAuth).
    let username: String

    init(oauthToken: String, username: String = "oauth2") {
        self.oauthToken = oauthToken
        self.username = username
    }

    /// Returns the authenticated remote URL by injecting credentials into the URL.
    /// Example: https://oauth2:token@gitlab.com/user/repo.git
    func authenticatedURL(for remoteURL: URL) -> URL? {
        guard var components = URLComponents(url: remoteURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.user = username
        components.password = oauthToken
        return components.url
    }
}

// MARK: - Git Author

/// Represents the author information for a Git commit.
struct GitAuthor: Sendable {
    let name: String
    let email: String
}

// MARK: - Clone Progress

/// Progress information during a clone operation.
struct CloneProgress: Sendable {
    /// The current phase of the clone operation.
    let phase: ClonePhase
    /// Progress percentage (0-100), nil if indeterminate.
    let percentage: Int?
    /// Human-readable description of current progress.
    let message: String

    enum ClonePhase: String, Sendable {
        case counting = "Counting objects"
        case compressing = "Compressing objects"
        case receiving = "Receiving objects"
        case resolving = "Resolving deltas"
        case checkingOut = "Checking out files"
        case done = "Done"
    }
}

// MARK: - Transfer Progress

/// Progress information during fetch/push operations.
struct TransferProgress: Sendable {
    /// Progress percentage (0-100), nil if indeterminate.
    let percentage: Int?
    /// Human-readable description of current progress.
    let message: String
    /// Whether the operation is complete.
    let isComplete: Bool
}

// MARK: - File Status

/// Represents the Git status of a file in the working directory.
struct FileStatus: Sendable, Identifiable, Equatable {
    var id: String { path }

    /// The file path relative to the repository root.
    let path: String
    /// The status of the file.
    let state: FileState

    /// Possible states for a tracked/untracked file.
    enum FileState: String, Sendable, Equatable {
        case modified = "M"
        case added = "A"
        case deleted = "D"
        case renamed = "R"
        case copied = "C"
        case untracked = "?"
        case ignored = "!"
        case unmerged = "U"
        case typeChanged = "T"

        var displayName: String {
            switch self {
            case .modified: return "Modified"
            case .added: return "Added"
            case .deleted: return "Deleted"
            case .renamed: return "Renamed"
            case .copied: return "Copied"
            case .untracked: return "Untracked"
            case .ignored: return "Ignored"
            case .unmerged: return "Unmerged"
            case .typeChanged: return "Type Changed"
            }
        }
    }
}

// MARK: - Git Operation Errors

/// Errors that can occur during Git operations.
enum GitOperationError: Error, LocalizedError, Equatable {
    case cloneFailed(String)
    case pullFailed(String)
    case pushFailed(String)
    case commitFailed(String)
    case statusFailed(String)
    case directoryConflict(String)
    case emptyCommit
    case invalidCommitMessage(String)
    case authenticationFailed(String)
    case networkError(String)
    case mergeConflict(String)
    case repositoryNotFound(String)
    case invalidRepository(String)

    var errorDescription: String? {
        switch self {
        case .cloneFailed(let output):
            return "Clone failed: \(output)"
        case .pullFailed(let output):
            return "Pull failed: \(output)"
        case .pushFailed(let output):
            return "Push failed: \(output)"
        case .commitFailed(let output):
            return "Commit failed: \(output)"
        case .statusFailed(let output):
            return "Status failed: \(output)"
        case .directoryConflict(let path):
            return "Directory conflict: '\(path)' already exists and is non-empty."
        case .emptyCommit:
            return "Cannot create an empty commit. No files are staged for commit."
        case .invalidCommitMessage(let reason):
            return "Invalid commit message: \(reason)"
        case .authenticationFailed(let output):
            return "Authentication failed: \(output)"
        case .networkError(let output):
            return "Network error: \(output)"
        case .mergeConflict(let output):
            return "Merge conflict: \(output)"
        case .repositoryNotFound(let path):
            return "Repository not found at path: \(path)"
        case .invalidRepository(let path):
            return "Invalid Git repository at path: \(path)"
        }
    }
}
