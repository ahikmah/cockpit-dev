import Foundation
import NIO
import NIOHTTP1
import NIOFoundationCompat
import OSLog

// MARK: - WebhookHTTPHandler

/// NIO channel handler that processes incoming HTTP requests for the webhook server.
///
/// This handler accumulates the request head and body, then delegates processing
/// to the WebhookServer actor. It responds with appropriate HTTP status codes.
final class WebhookHTTPHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let logger = Logger(subsystem: "dev.cockpit", category: "WebhookHTTPHandler")

    /// Reference to the webhook server actor for request processing.
    private let server: WebhookServer

    /// Accumulated request head.
    private var requestHead: HTTPRequestHead?

    /// Accumulated request body data.
    private var bodyBuffer: ByteBuffer = ByteBuffer()

    /// Creates a new handler with a reference to the webhook server.
    /// - Parameter server: The WebhookServer actor to delegate requests to.
    init(server: WebhookServer) {
        self.server = server
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)

        switch part {
        case .head(let head):
            self.requestHead = head
            self.bodyBuffer = context.channel.allocator.buffer(capacity: 0)

        case .body(var buffer):
            self.bodyBuffer.writeBuffer(&buffer)

        case .end:
            handleRequestEnd(context: context)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("Channel error: \(error.localizedDescription)")

        // Trigger server restart on connection errors
        Task {
            await server.restart()
        }

        context.close(promise: nil)
    }

    // MARK: - Private

    private func handleRequestEnd(context: ChannelHandlerContext) {
        guard let head = requestHead else {
            sendResponse(context: context, status: .badRequest, body: "Missing request head")
            return
        }

        // Only accept POST requests to the webhook endpoint
        guard head.method == .POST else {
            if head.method == .GET && head.uri == "/health" {
                sendResponse(context: context, status: .ok, body: "OK")
            } else {
                sendResponse(context: context, status: .methodNotAllowed, body: "Method not allowed")
            }
            return
        }

        // Accept POST to / or /webhook
        guard head.uri == "/" || head.uri == "/webhook" else {
            sendResponse(context: context, status: .notFound, body: "Not found")
            return
        }

        // Extract headers
        let eventHeader = head.headers["X-Gitlab-Event"].first
        let tokenHeader = head.headers["X-Gitlab-Token"].first

        // Convert body buffer to Data
        let bodyData: Data
        if let bytes = bodyBuffer.readBytes(length: bodyBuffer.readableBytes) {
            bodyData = Data(bytes)
        } else {
            bodyData = Data()
        }

        // Delegate to the server actor asynchronously
        let serverRef = self.server
        Task {
            await serverRef.handleRequest(
                eventHeader: eventHeader,
                tokenHeader: tokenHeader,
                body: bodyData
            )
        }

        // Always respond 200 OK to GitLab (even for invalid payloads)
        // This prevents GitLab from retrying and flooding the server
        sendResponse(context: context, status: .ok, body: "OK")
    }

    private func sendResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, body: String) {
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        headers.add(name: "Content-Length", value: "\(body.utf8.count)")
        headers.add(name: "Connection", value: "close")

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: headers)
        context.write(wrapOutboundOut(.head(head)), promise: nil)

        var buffer = context.channel.allocator.buffer(capacity: body.utf8.count)
        buffer.writeString(body)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)

        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }
}
