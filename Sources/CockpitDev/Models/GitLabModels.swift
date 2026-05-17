import Foundation

// MARK: - GitLab API Response Types

/// Represents a GitLab issue from the API.
struct GitLabIssue: Codable, Identifiable {
    let id: Int
    let iid: Int
    let projectId: Int
    let title: String
    let description: String?
    let state: String
    let labels: [String]
    let weight: Int?
    let assignee: GitLabUser?
    let assignees: [GitLabUser]?
    let milestone: GitLabMilestone?
    let createdAt: Date
    let updatedAt: Date
    let closedAt: Date?
    let dueDate: String?
    let webUrl: String

    enum CodingKeys: String, CodingKey {
        case id, iid, title, description, state, labels, weight
        case assignee, assignees, milestone
        case projectId = "project_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case closedAt = "closed_at"
        case dueDate = "due_date"
        case webUrl = "web_url"
    }
}

/// Represents a GitLab merge request from the API.
struct GitLabMR: Codable, Identifiable {
    let id: Int
    let iid: Int
    let projectId: Int
    let title: String
    let description: String?
    let state: String
    let sourceBranch: String
    let targetBranch: String
    let author: GitLabUser
    let assignee: GitLabUser?
    let pipeline: GitLabPipeline?
    let createdAt: Date
    let updatedAt: Date
    let mergedAt: Date?
    let closedAt: Date?
    let webUrl: String

    enum CodingKeys: String, CodingKey {
        case id, iid, title, description, state, author, assignee, pipeline
        case projectId = "project_id"
        case sourceBranch = "source_branch"
        case targetBranch = "target_branch"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case mergedAt = "merged_at"
        case closedAt = "closed_at"
        case webUrl = "web_url"
    }
}

/// Represents a GitLab user from the API.
struct GitLabUser: Codable, Identifiable {
    let id: Int
    let username: String
    let name: String
    let avatarUrl: String?
    let email: String?
    let state: String?
    let webUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, username, name, email, state
        case avatarUrl = "avatar_url"
        case webUrl = "web_url"
    }
}

/// Represents a GitLab project from the API.
struct GitLabProject: Codable, Identifiable {
    let id: Int
    let name: String
    let nameWithNamespace: String
    let path: String
    let pathWithNamespace: String
    let defaultBranch: String?
    let httpUrlToRepo: String
    let sshUrlToRepo: String
    let webUrl: String
    let visibility: String

    enum CodingKeys: String, CodingKey {
        case id, name, path, visibility
        case nameWithNamespace = "name_with_namespace"
        case pathWithNamespace = "path_with_namespace"
        case defaultBranch = "default_branch"
        case httpUrlToRepo = "http_url_to_repo"
        case sshUrlToRepo = "ssh_url_to_repo"
        case webUrl = "web_url"
    }
}


/// Represents a GitLab milestone from the API.
struct GitLabMilestone: Codable, Identifiable {
    let id: Int
    let iid: Int
    let projectId: Int?
    let title: String
    let description: String?
    let state: String
    let startDate: String?
    let dueDate: String?
    let createdAt: Date?
    let updatedAt: Date?
    let webUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, iid, title, description, state
        case projectId = "project_id"
        case startDate = "start_date"
        case dueDate = "due_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case webUrl = "web_url"
    }
}

/// Represents a GitLab branch from the API.
struct GitLabBranch: Codable {
    let name: String
    let merged: Bool
    let protected: Bool
    let developersCanPush: Bool
    let developersCanMerge: Bool
    let canPush: Bool
    let isDefault: Bool
    let webUrl: String?

    enum CodingKeys: String, CodingKey {
        case name, merged
        case `protected` = "protected"
        case developersCanPush = "developers_can_push"
        case developersCanMerge = "developers_can_merge"
        case canPush = "can_push"
        case isDefault = "default"
        case webUrl = "web_url"
    }
}

/// Represents a file diff in a GitLab merge request.
struct GitLabDiffFile: Codable {
    let oldPath: String
    let newPath: String
    let aMode: String?
    let bMode: String?
    let diff: String
    let newFile: Bool
    let renamedFile: Bool
    let deletedFile: Bool

    enum CodingKeys: String, CodingKey {
        case diff
        case oldPath = "old_path"
        case newPath = "new_path"
        case aMode = "a_mode"
        case bMode = "b_mode"
        case newFile = "new_file"
        case renamedFile = "renamed_file"
        case deletedFile = "deleted_file"
    }
}

/// Represents a discussion thread on a GitLab merge request.
struct GitLabDiscussion: Codable, Identifiable {
    let id: String
    let individualNote: Bool
    let notes: [GitLabNote]

    enum CodingKeys: String, CodingKey {
        case id, notes
        case individualNote = "individual_note"
    }
}

/// Represents a single note (comment) in a GitLab discussion.
struct GitLabNote: Codable, Identifiable {
    let id: Int
    let body: String
    let author: GitLabUser
    let createdAt: Date
    let updatedAt: Date
    let system: Bool
    let resolvable: Bool
    let resolved: Bool?
    let resolvedBy: GitLabUser?
    let position: GitLabNotePosition?

    enum CodingKeys: String, CodingKey {
        case id, body, author, system, resolvable, resolved, position
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case resolvedBy = "resolved_by"
    }
}

/// Position information for an inline diff note.
struct GitLabNotePosition: Codable {
    let baseSha: String?
    let startSha: String?
    let headSha: String?
    let oldPath: String?
    let newPath: String?
    let positionType: String?
    let oldLine: Int?
    let newLine: Int?

    enum CodingKeys: String, CodingKey {
        case oldLine, newLine
        case baseSha = "base_sha"
        case startSha = "start_sha"
        case headSha = "head_sha"
        case oldPath = "old_path"
        case newPath = "new_path"
        case positionType = "position_type"
    }
}

/// Represents a GitLab CI/CD pipeline from the API.
struct GitLabPipeline: Codable, Identifiable {
    let id: Int
    let status: String
    let ref: String
    let sha: String
    let webUrl: String?
    let createdAt: Date?
    let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, ref, sha
        case webUrl = "web_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Represents an item in a GitLab repository tree (file or directory).
struct GitLabTreeItem: Codable {
    let id: String
    let name: String
    let type: String  // "tree" for directory, "blob" for file
    let path: String
    let mode: String
}

/// Represents a commit from the GitLab API.
struct GitLabCommit: Codable {
    let id: String
    let shortId: String
    let title: String
    let message: String
    let authorName: String
    let authorEmail: String
    let committerName: String
    let committerEmail: String
    let createdAt: Date?
    let committedDate: Date?

    enum CodingKeys: String, CodingKey {
        case id, title, message
        case shortId = "short_id"
        case authorName = "author_name"
        case authorEmail = "author_email"
        case committerName = "committer_name"
        case committerEmail = "committer_email"
        case createdAt = "created_at"
        case committedDate = "committed_date"
    }
}
