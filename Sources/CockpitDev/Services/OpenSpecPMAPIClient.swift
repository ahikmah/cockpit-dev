import Foundation

enum OpenSpecPMFeatureStatus: String, Decodable {
    case pending = "PENDING"
    case assigned = "ASSIGNED"
    case inProgress = "IN_PROGRESS"
    case inReview = "IN_REVIEW"
    case completed = "COMPLETED"
    case archived = "ARCHIVED"
}

enum OpenSpecPMFeaturePriority: String, Decodable {
    case critical = "CRITICAL"
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
}

extension OpenSpecPMFeatureStatus {
    var ticketStatus: TicketStatus {
        switch self {
        case .pending: return .backlog
        case .assigned: return .todo
        case .inProgress: return .inProgress
        case .inReview: return .inReview
        case .completed, .archived: return .done
        }
    }
}

extension OpenSpecPMFeaturePriority {
    var ticketPriority: TicketPriority {
        switch self {
        case .critical: return .critical
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }
}

struct OpenSpecPMAssignee: Decodable {
    let name: String
    let username: String
}

struct OpenSpecPMFeature: Decodable {
    let id: String
    let externalIssueId: Int?
    let title: String
    let status: OpenSpecPMFeatureStatus
    let priority: OpenSpecPMFeaturePriority
    let startDate: Date?
    let dueDate: Date?
    let storyPoints: Int?
    let milestone: String?
    let branchName: String?
    let dependencies: [String]
    let assignee: OpenSpecPMAssignee?

    var dependencyReferences: [String] {
        dependencies
    }

    enum CodingKeys: String, CodingKey {
        case id
        case externalIssueId
        case title
        case status
        case priority
        case startDate
        case dueDate
        case storyPoints
        case milestone
        case branchName
        case dependencies
        case assignee
    }

    init(
        id: String,
        externalIssueId: Int?,
        title: String,
        status: OpenSpecPMFeatureStatus,
        priority: OpenSpecPMFeaturePriority,
        startDate: Date?,
        dueDate: Date?,
        storyPoints: Int?,
        milestone: String?,
        branchName: String?,
        dependencies: [String] = [],
        assignee: OpenSpecPMAssignee?
    ) {
        self.id = id
        self.externalIssueId = externalIssueId
        self.title = title
        self.status = status
        self.priority = priority
        self.startDate = startDate
        self.dueDate = dueDate
        self.storyPoints = storyPoints
        self.milestone = milestone
        self.branchName = branchName
        self.dependencies = dependencies
        self.assignee = assignee
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        externalIssueId = try container.decodeIfPresent(Int.self, forKey: .externalIssueId)
        title = try container.decode(String.self, forKey: .title)
        status = try container.decode(OpenSpecPMFeatureStatus.self, forKey: .status)
        priority = try container.decode(OpenSpecPMFeaturePriority.self, forKey: .priority)
        startDate = try container.decodeIfPresent(Date.self, forKey: .startDate)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        storyPoints = try container.decodeIfPresent(Int.self, forKey: .storyPoints)
        milestone = try container.decodeIfPresent(String.self, forKey: .milestone)
        branchName = try container.decodeIfPresent(String.self, forKey: .branchName)
        dependencies = try container.decodeIfPresent([String].self, forKey: .dependencies) ?? []
        assignee = try container.decodeIfPresent(OpenSpecPMAssignee.self, forKey: .assignee)
    }
}

enum OpenSpecPMAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case requestFailed(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "OpenSpec PM URL is invalid."
        case .invalidResponse:
            return "OpenSpec PM returned an invalid response."
        case .requestFailed(let status, let message):
            return "OpenSpec PM request failed (HTTP \(status)): \(message)"
        }
    }
}

protocol OpenSpecPMMetadataProviding {
    func fetchFeatures(repositoryURL: String) async throws -> [OpenSpecPMFeature]
}

final class OpenSpecPMAPIClient: OpenSpecPMMetadataProviding {
    private let baseURL: URL
    private let tokenProvider: () async throws -> String
    private let urlSession: URLSession

    init(
        baseURL: URL,
        tokenProvider: @escaping () async throws -> String,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.urlSession = urlSession
    }

    func fetchFeatures(repositoryURL: String) async throws -> [OpenSpecPMFeature] {
        guard var components = URLComponents(
            url: baseURL.appending(path: "api/native/features"),
            resolvingAgainstBaseURL: false
        ) else {
            throw OpenSpecPMAPIError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "repoUrl", value: repositoryURL)]
        guard let url = components.url else {
            throw OpenSpecPMAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(try await tokenProvider())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenSpecPMAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown server error"
            throw OpenSpecPMAPIError.requestFailed(httpResponse.statusCode, message)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([OpenSpecPMFeature].self, from: data)
    }
}
