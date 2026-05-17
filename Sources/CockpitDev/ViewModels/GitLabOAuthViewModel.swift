import Foundation
import AuthenticationServices
import SwiftUI

// MARK: - Connection State

/// Represents the current state of the GitLab connection flow.
enum GitLabConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(username: String, displayName: String, avatarURL: String?)
    case error(String)
    case needsReauthentication

    static func == (lhs: GitLabConnectionState, rhs: GitLabConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected):
            return true
        case (.connecting, .connecting):
            return true
        case let (.connected(u1, d1, a1), .connected(u2, d2, a2)):
            return u1 == u2 && d1 == d2 && a1 == a2
        case let (.error(e1), .error(e2)):
            return e1 == e2
        case (.needsReauthentication, .needsReauthentication):
            return true
        default:
            return false
        }
    }
}

// MARK: - GitLabOAuthViewModel

/// ViewModel for the GitLab Connect Sheet, managing OAuth flow state and user interaction.
@Observable
@MainActor
class GitLabOAuthViewModel {

    // MARK: - Published Properties

    /// The current connection state.
    private(set) var connectionState: GitLabConnectionState = .disconnected

    /// The GitLab instance URL input by the user.
    var instanceURLString: String = AppConstants.defaultGitLabInstanceURL

    /// The OAuth client ID input by the user.
    var clientId: String = ""

    /// The OAuth client secret input by the user (required for some GitLab instances).
    var clientSecret: String = ""

    /// Whether a disconnection warning should be shown.
    var showDisconnectWarning: Bool = false

    /// Warning message when revocation fails during disconnect.
    var revocationWarningMessage: String?

    /// Whether the disconnect confirmation dialog is shown.
    var showDisconnectConfirmation: Bool = false

    /// The connected user profile (if connected).
    private(set) var connectedUser: GitLabUser?

    // MARK: - Dependencies

    private let oauthService: GitLabOAuthService
    private let encryptionService: EncryptionService

    // MARK: - Initialization

    /// Creates a GitLabOAuthViewModel with the specified dependencies.
    /// - Parameters:
    ///   - oauthService: The GitLab OAuth service.
    ///   - encryptionService: The encryption service for token masking.
    init(oauthService: GitLabOAuthService, encryptionService: EncryptionService) {
        self.oauthService = oauthService
        self.encryptionService = encryptionService
    }

    // MARK: - Actions

    /// Checks the current connection status on view appear.
    func checkConnectionStatus() async {
        let hasToken = await oauthService.hasValidToken()
        if hasToken {
            // Update instance URL from stored data
            if let storedURL = await oauthService.getInstanceURL() {
                instanceURLString = storedURL.absoluteString
            }
            do {
                let user = try await oauthService.fetchCurrentUserProfile()
                connectedUser = user
                connectionState = .connected(
                    username: user.username,
                    displayName: user.name,
                    avatarURL: user.avatarUrl
                )
            } catch {
                // Token might be expired, try refresh
                let isExpired = await oauthService.isTokenExpired()
                if isExpired {
                    connectionState = .needsReauthentication
                } else {
                    connectionState = .error(error.localizedDescription)
                }
            }
        } else {
            connectionState = .disconnected
        }
    }

    /// Initiates the OAuth2 PKCE authentication flow.
    /// - Parameter contextProvider: The presentation context provider for ASWebAuthenticationSession.
    func connect(contextProvider: ASWebAuthenticationPresentationContextProviding) async {
        guard !clientId.isEmpty else {
            connectionState = .error("Please enter a valid OAuth Client ID.")
            return
        }

        guard let instanceURL = URL(string: instanceURLString),
              instanceURL.scheme != nil,
              instanceURL.host != nil else {
            connectionState = .error("Please enter a valid GitLab instance URL.")
            return
        }

        connectionState = .connecting

        do {
            // Store client ID for later refresh/revocation
            try await oauthService.storeClientId(clientId)

            let user = try await oauthService.authenticate(
                instanceURL: instanceURL,
                clientId: clientId,
                clientSecret: clientSecret.isEmpty ? nil : clientSecret,
                contextProvider: contextProvider
            )

            connectedUser = user
            connectionState = .connected(
                username: user.username,
                displayName: user.name,
                avatarURL: user.avatarUrl
            )
        } catch let error as GitLabOAuthError {
            switch error {
            case .userCancelled:
                connectionState = .disconnected
            default:
                connectionState = .error(error.localizedDescription)
            }
        } catch {
            connectionState = .error(error.localizedDescription)
        }
    }

    /// Disconnects the GitLab account, revoking the token and clearing local data.
    func disconnect() async {
        do {
            try await oauthService.disconnect { [weak self] warningMessage in
                Task { @MainActor in
                    self?.revocationWarningMessage = warningMessage
                    self?.showDisconnectWarning = true
                }
            }
            connectedUser = nil
            connectionState = .disconnected
        } catch {
            connectionState = .error("Failed to disconnect: \(error.localizedDescription)")
        }
    }

    /// Attempts to refresh the token when re-authentication is needed.
    func retryAuthentication(contextProvider: ASWebAuthenticationPresentationContextProviding) async {
        await connect(contextProvider: contextProvider)
    }

    /// Returns the masked access token for display purposes.
    func maskedToken() async -> String? {
        do {
            let token = try await oauthService.getValidToken()
            return encryptionService.maskToken(token)
        } catch {
            return nil
        }
    }

    /// Validates the instance URL format.
    var isInstanceURLValid: Bool {
        guard let url = URL(string: instanceURLString),
              let scheme = url.scheme,
              (scheme == "https" || scheme == "http"),
              url.host != nil else {
            return false
        }
        return true
    }

    /// Whether the connect button should be enabled.
    var canConnect: Bool {
        isInstanceURLValid && !clientId.isEmpty && connectionState != .connecting
    }
}
