import Foundation

// MARK: - GitLab API Errors

/// Errors that can occur during GitLab API operations.
enum GitLabAPIError: Error, LocalizedError {
    case invalidURL(String)
    case unauthorized
    case forbidden
    case notFound(String)
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(statusCode: Int, message: String)
    case networkError(Error)
    case decodingError(Error)
    case encodingError(Error)
    case maxRetriesExceeded(lastError: Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid URL: \(url)"
        case .unauthorized:
            return "Unauthorized. Please re-authenticate with GitLab."
        case .forbidden:
            return "Access forbidden. Insufficient permissions."
        case .notFound(let resource):
            return "Resource not found: \(resource)"
        case .rateLimited(let retryAfter):
            if let retryAfter = retryAfter {
                return "Rate limited. Retry after \(Int(retryAfter)) seconds."
            }
            return "Rate limited by GitLab API."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .maxRetriesExceeded(let lastError):
            return "Request failed after maximum retries. Last error: \(lastError.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from GitLab API."
        }
    }
}

// MARK: - Supporting Types

/// Fields that can be updated on a GitLab issue.
struct IssueUpdateFields: Encodable {
    var title: String?
    var description: String?
    var labels: [String]?
    var weight: Int?
    var assigneeIds: [Int]?
    var stateEvent: String?
    var startDate: String?
    var dueDate: String?
    var milestoneId: Int?
    var clearMilestone: Bool = false

    enum CodingKeys: String, CodingKey {
        case title, description, labels, weight
        case assigneeIds = "assignee_ids"
        case stateEvent = "state_event"
        case startDate = "start_date"
        case dueDate = "due_date"
        case milestoneId = "milestone_id"
    }
}

/// Position information for creating an inline diff note.
struct DiffPosition: Encodable, Equatable {
    let baseSha: String
    let startSha: String
    let headSha: String
    let oldPath: String
    let newPath: String
    let positionType: String
    let oldLine: Int?
    let newLine: Int?

    enum CodingKeys: String, CodingKey {
        case baseSha = "base_sha"
        case startSha = "start_sha"
        case headSha = "head_sha"
        case oldPath = "old_path"
        case newPath = "new_path"
        case positionType = "position_type"
        case oldLine = "old_line"
        case newLine = "new_line"
    }
}

/// Represents a paginated response from the GitLab API.
struct PaginatedResponse<T> {
    let items: [T]
    let nextPage: Int?
    let totalPages: Int?
    let totalItems: Int?
}

// MARK: - GitLabAPIClient

/// Actor-based GitLab API client providing thread-safe access to the GitLab REST API v4.
///
/// Features:
/// - Automatic retry with exponential backoff (3 attempts: 1s, 2s, 4s)
/// - Rate limiting detection (HTTP 429) with Retry-After header handling
/// - Pagination support for list endpoints
/// - JSON encoding/decoding with snake_case conversion
actor GitLabAPIClient {

    // MARK: - Properties

    private let baseURL: URL
    private let tokenProvider: () async throws -> String
    private let urlSession: URLSession

    /// Maximum number of retry attempts for failed requests.
    private let maxRetries: Int = 3

    /// Base delay for exponential backoff (in seconds).
    private let baseRetryDelay: TimeInterval = 1.0

    /// Default number of items per page for paginated requests.
    private let defaultPerPage: Int = 100

    /// JSON decoder configured for GitLab API responses.
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// JSON encoder configured for GitLab API requests.
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    // MARK: - Initialization

    /// Creates a GitLabAPIClient with the specified base URL and token provider.
    /// - Parameters:
    ///   - baseURL: The base URL of the GitLab instance (e.g., https://gitlab.com).
    ///   - tokenProvider: An async closure that provides a valid OAuth access token.
    ///   - urlSession: The URL session for network requests (default: .shared).
    init(baseURL: URL, tokenProvider: @escaping () async throws -> String, urlSession: URLSession = .shared) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
    }

    // MARK: - Issue Methods

    /// Creates a new issue in the specified project.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - title: The issue title (required).
    ///   - description: The issue description (optional).
    ///   - labels: Labels to assign to the issue.
    ///   - weight: Story points / weight (optional).
    ///   - assigneeId: The GitLab user ID to assign (optional).
    /// - Returns: The created GitLab issue.
    func createIssue(
        projectId: Int,
        title: String,
        description: String? = nil,
        labels: [String] = [],
        weight: Int? = nil,
        assigneeId: Int? = nil,
        startDate: String? = nil,
        dueDate: String? = nil,
        milestoneId: Int? = nil
    ) async throws -> GitLabIssue {
        let path = "/api/v4/projects/\(projectId)/issues"

        var body: [String: Any] = ["title": title]
        if let description = description {
            body["description"] = description
        }
        if !labels.isEmpty {
            body["labels"] = labels.joined(separator: ",")
        }
        if let weight = weight {
            body["weight"] = weight
        }
        if let assigneeId = assigneeId {
            body["assignee_ids"] = [assigneeId]
        }
        if let startDate = startDate {
            body["start_date"] = startDate
        }
        if let dueDate = dueDate {
            body["due_date"] = dueDate
        }
        if let milestoneId = milestoneId {
            body["milestone_id"] = milestoneId
        }

        return try await performRequest(method: "POST", path: path, body: body)
    }

    /// Updates an existing issue in the specified project.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - issueIid: The issue IID (internal ID within the project).
    ///   - fields: The fields to update.
    /// - Returns: The updated GitLab issue.
    func updateIssue(projectId: Int, issueIid: Int, fields: IssueUpdateFields) async throws -> GitLabIssue {
        let path = "/api/v4/projects/\(projectId)/issues/\(issueIid)"

        var body: [String: Any] = [:]
        if let title = fields.title { body["title"] = title }
        if let description = fields.description { body["description"] = description }
        if let labels = fields.labels { body["labels"] = labels.joined(separator: ",") }
        if let weight = fields.weight { body["weight"] = weight }
        if let assigneeIds = fields.assigneeIds { body["assignee_ids"] = assigneeIds }
        if let stateEvent = fields.stateEvent { body["state_event"] = stateEvent }
        if let startDate = fields.startDate { body["start_date"] = startDate }
        if let dueDate = fields.dueDate { body["due_date"] = dueDate }
        if fields.clearMilestone {
            body["milestone_id"] = NSNull()
        } else if let milestoneId = fields.milestoneId {
            body["milestone_id"] = milestoneId
        }

        return try await performRequest(method: "PUT", path: path, body: body)
    }

    /// Closes an issue in the specified project.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - issueIid: The issue IID to close.
    func closeIssue(projectId: Int, issueIid: Int) async throws {
        let path = "/api/v4/projects/\(projectId)/issues/\(issueIid)"
        let body: [String: Any] = ["state_event": "close"]
        let _: GitLabIssue = try await performRequest(method: "PUT", path: path, body: body)
    }

    /// Fetches issues from the specified project, optionally filtered by update date.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - updatedAfter: Only return issues updated after this date (optional).
    /// - Returns: An array of GitLab issues.
    func fetchIssues(projectId: Int, updatedAfter: Date? = nil) async throws -> [GitLabIssue] {
        let path = "/api/v4/projects/\(projectId)/issues"

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "state", value: "all"),
            URLQueryItem(name: "per_page", value: String(defaultPerPage))
        ]
        if let updatedAfter = updatedAfter {
            let formatter = ISO8601DateFormatter()
            queryItems.append(URLQueryItem(name: "updated_after", value: formatter.string(from: updatedAfter)))
        }

        return try await fetchAllPages(path: path, queryItems: queryItems)
    }

    // MARK: - Merge Request Methods

    /// Fetches merge requests from the specified project.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - state: The MR state filter (e.g., "opened", "merged", "closed").
    /// - Returns: An array of GitLab merge requests.
    func fetchMergeRequests(projectId: Int, state: String) async throws -> [GitLabMR] {
        let path = "/api/v4/projects/\(projectId)/merge_requests"

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "per_page", value: String(defaultPerPage))
        ]

        return try await fetchAllPages(path: path, queryItems: queryItems)
    }

    /// Fetches merge requests that GitLab relates to a specific issue.
    /// This captures links discovered from MR metadata and commit references.
    func fetchIssueRelatedMergeRequests(projectId: Int, issueIid: Int) async throws -> [GitLabMR] {
        let path = "/api/v4/projects/\(projectId)/issues/\(issueIid)/related_merge_requests"
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "per_page", value: String(defaultPerPage))
        ]

        return try await fetchAllPages(path: path, queryItems: queryItems)
    }

    /// Fetches issue notes, including GitLab system notes such as MR mentions.
    func fetchIssueNotes(projectId: Int, issueIid: Int) async throws -> [GitLabNote] {
        let path = "/api/v4/projects/\(projectId)/issues/\(issueIid)/notes"
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "per_page", value: String(defaultPerPage))
        ]

        return try await fetchAllPages(path: path, queryItems: queryItems)
    }

    /// Fetches the diff files for a merge request.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - mrIid: The merge request IID.
    /// - Returns: An array of diff files.
    func fetchMRDiff(projectId: Int, mrIid: Int) async throws -> [GitLabDiffFile] {
        let path = "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/changes"

        struct MRChangesResponse: Decodable {
            let changes: [GitLabDiffFile]
        }

        let response: MRChangesResponse = try await performRequest(method: "GET", path: path)
        return response.changes
    }

    /// Fetches commits included in a merge request.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - mrIid: The merge request IID.
    /// - Returns: Commits attached to the merge request.
    func fetchMRCommits(projectId: Int, mrIid: Int) async throws -> [GitLabCommit] {
        let path = "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/commits"
        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "per_page", value: String(defaultPerPage))
        ]
        return try await fetchAllPages(path: path, queryItems: queryItems)
    }

    /// Fetches discussions (comment threads) for a merge request.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - mrIid: The merge request IID.
    /// - Returns: An array of discussions.
    func fetchMRDiscussions(projectId: Int, mrIid: Int) async throws -> [GitLabDiscussion] {
        let path = "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/discussions"

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "per_page", value: String(defaultPerPage))
        ]

        return try await fetchAllPages(path: path, queryItems: queryItems)
    }

    /// Creates a note (comment) on a merge request.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - mrIid: The merge request IID.
    ///   - body: The comment body text.
    ///   - position: Optional diff position for inline comments.
    func createMRNote(projectId: Int, mrIid: Int, body: String, position: DiffPosition? = nil) async throws {
        let path = "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/discussions"

        var requestBody: [String: Any] = ["body": body]

        if let position = position {
            var positionDict: [String: Any] = [
                "base_sha": position.baseSha,
                "start_sha": position.startSha,
                "head_sha": position.headSha,
                "old_path": position.oldPath,
                "new_path": position.newPath,
                "position_type": position.positionType
            ]
            if let oldLine = position.oldLine {
                positionDict["old_line"] = oldLine
            }
            if let newLine = position.newLine {
                positionDict["new_line"] = newLine
            }
            requestBody["position"] = positionDict
        }

        struct NoteResponse: Decodable {
            let id: String
        }

        let _: NoteResponse = try await performRequest(method: "POST", path: path, body: requestBody)
    }

    /// Approves a merge request.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - mrIid: The merge request IID.
    func approveMR(projectId: Int, mrIid: Int) async throws {
        let path = "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/approve"
        let _: EmptyResponse = try await performRequest(method: "POST", path: path)
    }

    /// Merges a merge request.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - mrIid: The merge request IID.
    /// - Returns: The merged MR.
    func mergeMR(projectId: Int, mrIid: Int) async throws -> GitLabMR {
        let path = "/api/v4/projects/\(projectId)/merge_requests/\(mrIid)/merge"
        return try await performRequest(method: "PUT", path: path)
    }

    // MARK: - User Methods

    /// Searches for GitLab users by query string.
    /// - Parameter query: The search query (username or name).
    /// - Returns: An array of matching users.
    func searchUsers(query: String) async throws -> [GitLabUser] {
        let path = "/api/v4/users"

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "per_page", value: "20")
        ]

        return try await performRequest(method: "GET", path: path, queryItems: queryItems)
    }

    /// Fetches the currently authenticated user's profile.
    /// - Returns: The current user.
    func getCurrentUser() async throws -> GitLabUser {
        let path = "/api/v4/user"
        return try await performRequest(method: "GET", path: path)
    }

    // MARK: - Project Methods

    /// Validates that the authenticated user has access to a project by URL.
    /// - Parameter url: The repository URL (HTTP or SSH).
    /// - Returns: The GitLab project if accessible.
    func validateProjectAccess(url: String) async throws -> GitLabProject {
        // Extract project path from URL
        let projectPath = extractProjectPath(from: url)

        guard !projectPath.isEmpty else {
            throw GitLabAPIError.invalidURL(url)
        }

        // GitLab API requires the project path to be URL-encoded with %2F for slashes
        // We must construct the URL manually because URLComponents decodes %2F
        let encodedPath = projectPath.replacingOccurrences(of: "/", with: "%2F")
        let urlString = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/v4/projects/" + encodedPath

        guard let requestURL = URL(string: urlString) else {
            throw GitLabAPIError.invalidURL(url)
        }

        let token = try await tokenProvider()
        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            switch httpResponse.statusCode {
            case 401:
                throw GitLabAPIError.unauthorized
            case 404:
                let message = String(data: data, encoding: .utf8) ?? "Not found"
                throw GitLabAPIError.notFound(message)
            default:
                let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw GitLabAPIError.serverError(statusCode: httpResponse.statusCode, message: message)
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitLabProject.self, from: data)
    }

    // MARK: - Milestone Methods

    /// Fetches milestones from the specified project.
    /// - Parameter projectId: The GitLab project ID.
    /// - Returns: An array of GitLab milestones.
    func fetchMilestones(projectId: Int) async throws -> [GitLabMilestone] {
        let path = "/api/v4/projects/\(projectId)/milestones"

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "per_page", value: String(defaultPerPage))
        ]

        return try await fetchAllPages(path: path, queryItems: queryItems)
    }

    /// Creates a milestone in the specified project.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - title: The milestone title.
    ///   - startDate: The milestone start date.
    ///   - dueDate: The milestone due date.
    /// - Returns: The created milestone.
    func createMilestone(projectId: Int, title: String, startDate: Date, dueDate: Date) async throws -> GitLabMilestone {
        let path = "/api/v4/projects/\(projectId)/milestones"

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let body: [String: Any] = [
            "title": title,
            "start_date": dateFormatter.string(from: startDate),
            "due_date": dateFormatter.string(from: dueDate)
        ]

        return try await performRequest(method: "POST", path: path, body: body)
    }

    /// Deletes a milestone from the specified project.
    func deleteMilestone(projectId: Int, milestoneId: Int) async throws {
        let path = "/api/v4/projects/\(projectId)/milestones/\(milestoneId)"
        _ = try await performRawRequest(method: "DELETE", path: path)
    }

    // MARK: - Repository File Methods

    /// Fetches the content of a file from the repository.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - filePath: The path to the file in the repository.
    ///   - ref: The branch, tag, or commit SHA to read from.
    /// - Returns: The decoded file content as a string.
    func fetchFileContent(projectId: Int, filePath: String, ref: String) async throws -> String {
        let encodedFilePath = filePath.addingPercentEncoding(
            withAllowedCharacters: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        ) ?? filePath
        let path = "/api/v4/projects/\(projectId)/repository/files/\(encodedFilePath)"

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "ref", value: ref)
        ]

        struct FileResponse: Decodable {
            let content: String
            let encoding: String
        }

        let response: FileResponse = try await performRequest(method: "GET", path: path, queryItems: queryItems)

        guard response.encoding == "base64" else {
            return response.content
        }

        guard let data = Data(base64Encoded: response.content),
              let content = String(data: data, encoding: .utf8) else {
            throw GitLabAPIError.decodingError(
                NSError(domain: "GitLabAPIClient", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to decode base64 file content"])
            )
        }

        return content
    }

    /// Fetches all branches for the specified project.
    /// - Parameter projectId: The GitLab project ID.
    /// - Returns: An array of branches.
    func fetchBranches(projectId: Int) async throws -> [GitLabBranch] {
        let path = "/api/v4/projects/\(projectId)/repository/branches"

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "per_page", value: String(defaultPerPage))
        ]

        return try await fetchAllPages(path: path, queryItems: queryItems)
    }

    /// Fetches the repository tree (directory listing) for a given path and ref.
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - path: The directory path within the repository.
    ///   - ref: The branch, tag, or commit SHA.
    /// - Returns: An array of tree items (files and directories).
    func fetchRepositoryTree(projectId: Int, path: String, ref: String) async throws -> [GitLabTreeItem] {
        let apiPath = "/api/v4/projects/\(projectId)/repository/tree"

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "ref", value: ref),
            URLQueryItem(name: "per_page", value: String(defaultPerPage))
        ]

        return try await fetchAllPages(path: apiPath, queryItems: queryItems)
    }

    /// Fetches the commit history for a specific file on a given branch.
    ///
    /// Used to extract git commit metadata (author, timestamp) for spec versioning.
    ///
    /// - Parameters:
    ///   - projectId: The GitLab project ID.
    ///   - filePath: The path to the file in the repository.
    ///   - ref: The branch, tag, or commit SHA.
    ///   - perPage: Number of commits to fetch (default: 1 for latest only).
    /// - Returns: An array of commits that modified the file.
    func fetchFileCommits(projectId: Int, filePath: String, ref: String, perPage: Int = 1) async throws -> [GitLabCommit] {
        let apiPath = "/api/v4/projects/\(projectId)/repository/commits"

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "path", value: filePath),
            URLQueryItem(name: "ref_name", value: ref),
            URLQueryItem(name: "per_page", value: String(perPage))
        ]

        return try await performRequest(method: "GET", path: apiPath, queryItems: queryItems)
    }

    // MARK: - Pagination Support

    /// Fetches all pages of a paginated endpoint.
    /// - Parameters:
    ///   - path: The API path.
    ///   - queryItems: Query parameters for the request.
    /// - Returns: All items across all pages.
    private func fetchAllPages<T: Decodable>(path: String, queryItems: [URLQueryItem] = []) async throws -> [T] {
        var allItems: [T] = []
        var currentPage = 1
        var hasMorePages = true

        while hasMorePages {
            var pageQueryItems = queryItems
            pageQueryItems.append(URLQueryItem(name: "page", value: String(currentPage)))

            if !pageQueryItems.contains(where: { $0.name == "per_page" }) {
                pageQueryItems.append(URLQueryItem(name: "per_page", value: String(defaultPerPage)))
            }

            let (data, response) = try await performRawRequest(method: "GET", path: path, queryItems: pageQueryItems)

            let items = try decoder.decode([T].self, from: data)
            allItems.append(contentsOf: items)

            // Check pagination headers
            var hasExplicitNextPage = false
            if let httpResponse = response as? HTTPURLResponse {
                let nextPage = httpResponse.value(forHTTPHeaderField: "X-Next-Page")
                let totalPages = httpResponse.value(forHTTPHeaderField: "X-Total-Pages")

                if let nextPageStr = nextPage, let next = Int(nextPageStr), !nextPageStr.isEmpty {
                    currentPage = next
                    hasExplicitNextPage = true
                } else if let totalPagesStr = totalPages, let total = Int(totalPagesStr), currentPage < total {
                    currentPage += 1
                    hasExplicitNextPage = true
                } else {
                    hasMorePages = false
                }
            } else {
                hasMorePages = false
            }

            // Safety: stop if we got fewer items than per_page and no explicit next page
            if !hasExplicitNextPage && items.count < defaultPerPage {
                hasMorePages = false
            }
        }

        return allItems
    }

    // MARK: - HTTP Request Infrastructure

    /// Performs a typed request with automatic retry and error handling.
    private func performRequest<T: Decodable>(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) async throws -> T {
        let (data, _) = try await performRawRequest(method: method, path: path, queryItems: queryItems, body: body)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw GitLabAPIError.decodingError(error)
        }
    }

    /// Performs a raw HTTP request with retry logic and rate limiting handling.
    /// - Returns: The response data and URL response.
    private func performRawRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) async throws -> (Data, URLResponse) {
        var lastError: Error = GitLabAPIError.invalidResponse
        var currentDelay = baseRetryDelay

        for attempt in 1...maxRetries {
            do {
                let request = try await buildRequest(method: method, path: path, queryItems: queryItems, body: body)
                let (data, response) = try await urlSession.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw GitLabAPIError.invalidResponse
                }

                // Handle rate limiting (429)
                if httpResponse.statusCode == 429 {
                    let retryAfter = parseRetryAfter(from: httpResponse)
                    let waitTime = retryAfter ?? currentDelay
                    if attempt < maxRetries {
                        try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                        currentDelay *= 2
                        continue
                    }
                    throw GitLabAPIError.rateLimited(retryAfter: retryAfter)
                }

                // Handle success
                if (200...299).contains(httpResponse.statusCode) {
                    return (data, response)
                }

                // Handle specific error codes
                switch httpResponse.statusCode {
                case 401:
                    throw GitLabAPIError.unauthorized
                case 403:
                    throw GitLabAPIError.forbidden
                case 404:
                    let message = String(data: data, encoding: .utf8) ?? "Not found"
                    throw GitLabAPIError.notFound(message)
                default:
                    let message = String(data: data, encoding: .utf8) ?? "Unknown error"
                    let error = GitLabAPIError.serverError(statusCode: httpResponse.statusCode, message: message)
                    if attempt < maxRetries && httpResponse.statusCode >= 500 {
                        lastError = error
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                        continue
                    }
                    throw error
                }
            } catch let error as GitLabAPIError {
                // Don't retry client errors (except rate limiting which is handled above)
                switch error {
                case .unauthorized, .forbidden, .notFound, .invalidURL, .decodingError, .encodingError:
                    throw error
                case .rateLimited:
                    if attempt == maxRetries {
                        throw error
                    }
                    // Already handled above
                    lastError = error
                default:
                    lastError = error
                    if attempt < maxRetries {
                        try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                        currentDelay *= 2
                        continue
                    }
                }
            } catch {
                lastError = GitLabAPIError.networkError(error)
                if attempt < maxRetries {
                    try await Task.sleep(nanoseconds: UInt64(currentDelay * 1_000_000_000))
                    currentDelay *= 2
                    continue
                }
            }
        }

        throw GitLabAPIError.maxRetriesExceeded(lastError: lastError)
    }

    /// Builds an authenticated URLRequest.
    private func buildRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) async throws -> URLRequest {
        let token = try await tokenProvider()

        // Build URL string directly to preserve percent-encoding (e.g., %2F in project paths)
        let urlString = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path
        var components = URLComponents(string: urlString)!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw GitLabAPIError.invalidURL(path)
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body = body {
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw GitLabAPIError.encodingError(error)
            }
        }

        return request
    }

    /// Parses the Retry-After header from an HTTP response.
    private func parseRetryAfter(from response: HTTPURLResponse) -> TimeInterval? {
        guard let retryAfterStr = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }

        // Try parsing as seconds
        if let seconds = TimeInterval(retryAfterStr) {
            return seconds
        }

        // Try parsing as HTTP date
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter.date(from: retryAfterStr) {
            return max(0, date.timeIntervalSinceNow)
        }

        return nil
    }

    /// Extracts the project path from a GitLab repository URL.
    /// Supports both HTTPS and SSH URL formats.
    private func extractProjectPath(from url: String) -> String {
        var path = url

        // Handle SSH URLs (git@gitlab.com:namespace/project.git)
        if path.contains("@") && path.contains(":") {
            if let colonIndex = path.lastIndex(of: ":") {
                path = String(path[path.index(after: colonIndex)...])
            }
        } else {
            // Handle HTTPS URLs
            if let urlObj = URL(string: path) {
                path = urlObj.path
            }
        }

        // Remove leading slash
        if path.hasPrefix("/") {
            path = String(path.dropFirst())
        }

        // Remove .git suffix
        if path.hasSuffix(".git") {
            path = String(path.dropLast(4))
        }

        return path
    }
}

// MARK: - Empty Response Helper

/// A decodable type for API responses that return empty or minimal JSON.
private struct EmptyResponse: Decodable {}
