import Foundation
import NIO
import NIOHTTP1
import NIOFoundationCompat
import OSLog

// MARK: - WebhookServer

/// Actor-based local HTTP server that receives GitLab webhook events.
///
/// The server listens on a configurable port (default 9876) and processes
/// incoming webhook payloads for issues, merge requests, pushes, and pipelines.
///
/// Features:
/// - Port binding with fallback (ports 9876-9886)
/// - Token validation via x-gitlab-token header
/// - Duplicate event detection (same ID + same updated_at)
/// - Malformed payload handling (log and discard)
/// - Automatic restart on connection errors
actor WebhookServer {

    // MARK: - Properties

    private let logger = Logger(subsystem: "dev.cockpit", category: "WebhookServer")

    /// The NIO event loop group for the server.
    private var eventLoopGroup: MultiThreadedEventLoopGroup?

    /// The bound server channel.
    private var serverChannel: Channel?

    /// The port the server is currently bound to, or nil if not running.
    private(set) var boundPort: Int?

    /// Whether the server is currently running.
    private(set) var isRunning: Bool = false

    /// The secret token used to validate incoming webhook requests.
    private var secretToken: String?

    /// Cache of recently processed events for duplicate detection.
    /// Key: "\(eventType):\(objectId):\(updatedAt)"
    private var processedEvents: [String: Date] = [:]

    /// Maximum number of entries in the processed events cache.
    private let maxProcessedEventsCache: Int = 1000

    /// Time-to-live for processed event entries (5 minutes).
    private let processedEventsTTL: TimeInterval = 300

    /// Callback invoked when a valid webhook event is received.
    private var eventHandler: ((WebhookEvent) async -> Void)?

    /// Whether the server should attempt automatic restart on errors.
    private var autoRestartEnabled: Bool = true

    /// Number of consecutive restart attempts.
    private var restartAttempts: Int = 0

    /// Maximum restart attempts before giving up.
    private let maxRestartAttempts: Int = 5

    // MARK: - Initialization

    /// Creates a new WebhookServer instance.
    /// - Parameters:
    ///   - secretToken: The token to validate against x-gitlab-token header.
    ///   - eventHandler: Callback invoked when a valid event is received.
    init(secretToken: String? = nil, eventHandler: ((WebhookEvent) async -> Void)? = nil) {
        self.secretToken = secretToken
        self.eventHandler = eventHandler
    }

    // MARK: - Configuration

    /// Updates the secret token used for webhook validation.
    func setSecretToken(_ token: String?) {
        self.secretToken = token
    }

    /// Sets the event handler callback.
    func setEventHandler(_ handler: @escaping (WebhookEvent) async -> Void) {
        self.eventHandler = handler
    }

    // MARK: - Server Lifecycle

    /// Starts the webhook server on the specified port.
    ///
    /// If the specified port is unavailable, tries ports in the range 9876-9886.
    /// If all ports are exhausted, throws `WebhookError.allPortsExhausted`.
    ///
    /// - Parameter port: The preferred port to bind to (default: 9876).
    /// - Throws: `WebhookError.allPortsExhausted` if no port is available.
    func start(port: Int = AppConstants.defaultWebhookPort) async throws {
        guard !isRunning else {
            throw WebhookError.serverAlreadyRunning
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.eventLoopGroup = group

        // Try ports in the configured range
        let portRange = AppConstants.webhookPortRange

        for candidatePort in portRange {
            do {
                try await bindToPort(candidatePort, group: group)
                self.boundPort = candidatePort
                self.isRunning = true
                self.restartAttempts = 0
                logger.info("Webhook server started on port \(candidatePort)")
                return
            } catch {
                logger.warning("Failed to bind to port \(candidatePort): \(error.localizedDescription)")
                continue
            }
        }

        // All ports exhausted - clean up and throw
        try? await shutdownGroup(group)
        self.eventLoopGroup = nil
        logger.error("All webhook ports exhausted. Falling back to polling-only mode.")
        throw WebhookError.allPortsExhausted
    }

    /// Stops the webhook server and releases resources.
    func stop() async {
        guard isRunning else { return }

        autoRestartEnabled = false

        if let channel = serverChannel {
            do {
                try await channel.close().get()
            } catch {
                logger.warning("Error closing server channel: \(error.localizedDescription)")
            }
            self.serverChannel = nil
        }

        if let group = eventLoopGroup {
            try? await shutdownGroup(group)
            self.eventLoopGroup = nil
        }

        self.isRunning = false
        self.boundPort = nil
        self.autoRestartEnabled = true
        logger.info("Webhook server stopped")
    }

    /// Attempts to restart the server after a connection error.
    func restart() async {
        guard autoRestartEnabled else { return }
        guard restartAttempts < maxRestartAttempts else {
            logger.error("Max restart attempts (\(self.maxRestartAttempts)) reached. Server will not restart.")
            return
        }

        restartAttempts += 1
        let previousPort = boundPort ?? AppConstants.defaultWebhookPort

        logger.info("Attempting server restart (attempt \(self.restartAttempts)/\(self.maxRestartAttempts))")

        // Clean up existing state
        if let channel = serverChannel {
            try? await channel.close().get()
            self.serverChannel = nil
        }
        if let group = eventLoopGroup {
            try? await shutdownGroup(group)
            self.eventLoopGroup = nil
        }
        self.isRunning = false
        self.boundPort = nil

        // Wait before restart (exponential backoff)
        let delay = UInt64(pow(2.0, Double(restartAttempts - 1))) * 1_000_000_000
        try? await Task.sleep(nanoseconds: delay)

        do {
            try await start(port: previousPort)
        } catch {
            logger.error("Restart failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Token Validation

    /// Validates the x-gitlab-token header against the configured secret.
    /// - Parameter tokenHeader: The value of the x-gitlab-token header from the request.
    /// - Returns: `true` if the token is valid or no secret is configured.
    func validateToken(_ tokenHeader: String?) -> Bool {
        // If no secret token is configured, accept all requests
        guard let secret = secretToken, !secret.isEmpty else {
            return true
        }

        guard let token = tokenHeader else {
            return false
        }

        return token == secret
    }

    // MARK: - Event Parsing

    /// Parses a webhook event from the request headers and body.
    /// - Parameters:
    ///   - eventHeader: The value of the X-Gitlab-Event header.
    ///   - body: The raw request body data.
    /// - Returns: The parsed `WebhookEvent`.
    /// - Throws: `WebhookError` if the payload is malformed or the event type is unknown.
    func parseEvent(eventHeader: String, body: Data) throws -> WebhookEvent {
        let decoder = JSONDecoder()

        switch eventHeader {
        case "Issue Hook":
            do {
                let payload = try decoder.decode(IssueWebhookPayload.self, from: body)
                return .issueHook(payload)
            } catch {
                throw WebhookError.malformedPayload(reason: "Invalid Issue Hook payload: \(error.localizedDescription)")
            }

        case "Merge Request Hook":
            do {
                let payload = try decoder.decode(MRWebhookPayload.self, from: body)
                return .mergeRequestHook(payload)
            } catch {
                throw WebhookError.malformedPayload(reason: "Invalid Merge Request Hook payload: \(error.localizedDescription)")
            }

        case "Push Hook":
            do {
                let payload = try decoder.decode(PushWebhookPayload.self, from: body)
                return .pushHook(payload)
            } catch {
                throw WebhookError.malformedPayload(reason: "Invalid Push Hook payload: \(error.localizedDescription)")
            }

        case "Pipeline Hook":
            do {
                let payload = try decoder.decode(PipelineWebhookPayload.self, from: body)
                return .pipelineHook(payload)
            } catch {
                throw WebhookError.malformedPayload(reason: "Invalid Pipeline Hook payload: \(error.localizedDescription)")
            }

        default:
            throw WebhookError.unknownEventType(eventHeader)
        }
    }

    // MARK: - Duplicate Detection

    /// Checks if an event is a duplicate based on its identifier and timestamp.
    /// - Parameters:
    ///   - eventType: The type of event (e.g., "issue", "merge_request").
    ///   - objectId: The ID of the object (issue ID, MR ID, etc.).
    ///   - updatedAt: The updated_at timestamp from the payload.
    /// - Returns: `true` if this event has already been processed (is a duplicate).
    func isDuplicateEvent(eventType: String, objectId: Int, updatedAt: String) -> Bool {
        let key = "\(eventType):\(objectId):\(updatedAt)"

        // Clean up expired entries periodically
        cleanupExpiredEvents()

        if processedEvents[key] != nil {
            logger.debug("Duplicate event detected: \(key)")
            return true
        }

        // Record this event
        processedEvents[key] = Date()
        return false
    }

    /// Generates a deduplication key for a webhook event.
    /// - Parameter event: The webhook event to generate a key for.
    /// - Returns: A tuple of (eventType, objectId, updatedAt) or nil if not applicable.
    func deduplicationInfo(for event: WebhookEvent) -> (eventType: String, objectId: Int, updatedAt: String)? {
        switch event {
        case .issueHook(let payload):
            return ("issue", payload.objectAttributes.id, payload.objectAttributes.updatedAt)
        case .mergeRequestHook(let payload):
            return ("merge_request", payload.objectAttributes.id, payload.objectAttributes.updatedAt)
        case .pipelineHook(let payload):
            return ("pipeline", payload.objectAttributes.id, payload.objectAttributes.createdAt)
        case .pushHook:
            // Push events don't have a meaningful deduplication key
            return nil
        }
    }

    // MARK: - Internal Request Handling

    /// Handles an incoming HTTP request from the NIO channel handler.
    /// This is called by the channel handler on the event loop.
    func handleRequest(eventHeader: String?, tokenHeader: String?, body: Data) async {
        // Validate token
        guard validateToken(tokenHeader) else {
            logger.warning("Webhook request rejected: invalid token")
            return
        }

        // Validate event header
        guard let eventHeader = eventHeader, !eventHeader.isEmpty else {
            logger.warning("Webhook request rejected: missing X-Gitlab-Event header")
            return
        }

        // Parse event
        let event: WebhookEvent
        do {
            event = try parseEvent(eventHeader: eventHeader, body: body)
        } catch let error as WebhookError {
            switch error {
            case .malformedPayload(let reason):
                logger.warning("Malformed webhook payload discarded: \(reason)")
            case .unknownEventType(let type):
                logger.info("Unknown webhook event type ignored: \(type)")
            default:
                logger.warning("Webhook parsing error: \(error.localizedDescription)")
            }
            return
        } catch {
            logger.warning("Unexpected webhook parsing error: \(error.localizedDescription)")
            return
        }

        // Check for duplicates
        if let dedup = deduplicationInfo(for: event) {
            if isDuplicateEvent(eventType: dedup.eventType, objectId: dedup.objectId, updatedAt: dedup.updatedAt) {
                logger.debug("Duplicate webhook event discarded")
                return
            }
        }

        // Deliver event to handler
        if let handler = eventHandler {
            await handler(event)
        }
    }

    // MARK: - Private Helpers

    /// Binds the server to the specified port.
    private func bindToPort(_ port: Int, group: EventLoopGroup) async throws {
        let server = self

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(WebhookHTTPHandler(server: server))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 1)

        do {
            let channel = try await bootstrap.bind(host: "127.0.0.1", port: port).get()
            self.serverChannel = channel
        } catch {
            throw WebhookError.portBindingFailed(port: port)
        }
    }

    /// Shuts down the event loop group gracefully.
    private func shutdownGroup(_ group: MultiThreadedEventLoopGroup) async throws {
        try await group.shutdownGracefully()
    }

    /// Removes expired entries from the processed events cache.
    private func cleanupExpiredEvents() {
        let now = Date()
        processedEvents = processedEvents.filter { _, timestamp in
            now.timeIntervalSince(timestamp) < processedEventsTTL
        }

        // If still over capacity, remove oldest entries
        if processedEvents.count > maxProcessedEventsCache {
            let sorted = processedEvents.sorted { $0.value < $1.value }
            let toRemove = processedEvents.count - maxProcessedEventsCache
            for (key, _) in sorted.prefix(toRemove) {
                processedEvents.removeValue(forKey: key)
            }
        }
    }
}
