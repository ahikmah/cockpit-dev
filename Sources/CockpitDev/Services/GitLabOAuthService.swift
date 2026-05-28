import Foundation
import AuthenticationServices
import CryptoKit

// MARK: - OAuth Errors

/// Errors that can occur during GitLab OAuth operations.
enum GitLabOAuthError: Error, LocalizedError {
    case invalidInstanceURL
    case authenticationFailed(String)
    case tokenExchangeFailed(String)
    case tokenRefreshFailed(String)
    case tokenRevocationFailed(String)
    case tokenNotFound
    case tokenExpired
    case networkError(String)
    case invalidResponse
    case userCancelled

    var errorDescription: String? {
        switch self {
        case .invalidInstanceURL:
            return "Invalid GitLab instance URL. Please provide a valid HTTPS URL."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .tokenExchangeFailed(let reason):
            return "Token exchange failed: \(reason)"
        case .tokenRefreshFailed(let reason):
            return "Token refresh failed: \(reason)"
        case .tokenRevocationFailed(let reason):
            return "Token revocation failed: \(reason)"
        case .tokenNotFound:
            return "No stored authentication token found."
        case .tokenExpired:
            return "Authentication token has expired. Please re-authenticate."
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .invalidResponse:
            return "Invalid response from GitLab server."
        case .userCancelled:
            return "Authentication was cancelled."
        }
    }
}

// MARK: - OAuth Token Response

/// Represents the OAuth2 token response from GitLab.
struct OAuthTokenResponse: Codable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let createdAt: Int
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case createdAt = "created_at"
        case scope
    }
}

// MARK: - Stored Token Data

/// Represents the locally stored token data (encrypted in Keychain).
struct StoredTokenData: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let instanceURL: String
    let scope: String?
}

// MARK: - GitLab OAuth Configuration

/// Configuration for GitLab OAuth2 PKCE flow.
struct GitLabOAuthConfig {
    let instanceURL: URL
    let clientId: String
    let redirectURI: String
    let scopes: [String]

    /// Default OAuth scopes required by Cockpit Dev.
    static let defaultScopes = ["api", "read_user", "read_repository"]

    /// The redirect URI scheme used for the OAuth callback.
    static let callbackScheme = "cockpitdev"

    /// The full redirect URI.
    static let defaultRedirectURI = "cockpitdev://oauth/callback"

    /// Default client ID (user should configure their own GitLab OAuth application).
    static let defaultClientId = "cockpitdev-oauth-client"
}

// MARK: - GitLabOAuthService

/// Actor-based service responsible for GitLab OAuth2 PKCE authentication,
/// token management, refresh, and account disconnection.
///
/// Thread-safe via Swift actor isolation. Stores tokens encrypted via EncryptionService.
actor GitLabOAuthService {

    // MARK: - Properties

    private let encryptionService: EncryptionService
    private let urlSession: URLSession

    /// Keychain keys for stored credentials.
    private enum KeychainKeys {
        static let tokenData = "gitlab.oauth.tokenData"
        static let clientId = "gitlab.oauth.clientId"
        static let instanceURL = "gitlab.oauth.instanceURL"
    }

    /// The currently stored token data (cached in memory after first load).
    private var cachedTokenData: StoredTokenData?

    /// Whether a token refresh is currently in progress.
    private var isRefreshing: Bool = false

    // MARK: - Initialization

    /// Creates a GitLabOAuthService with the specified dependencies.
    /// - Parameters:
    ///   - encryptionService: The encryption service for secure token storage.
    ///   - urlSession: The URL session for network requests (default: .shared).
    init(encryptionService: EncryptionService, urlSession: URLSession = .shared) {
        self.encryptionService = encryptionService
        self.urlSession = urlSession
    }

    // MARK: - OAuth2 PKCE Flow

    /// Initiates the OAuth2 PKCE authentication flow using ASWebAuthenticationSession.
    /// - Parameters:
    ///   - instanceURL: The GitLab instance URL (default: https://gitlab.com).
    ///   - clientId: The OAuth application client ID.
    ///   - contextProvider: The presentation context provider for ASWebAuthenticationSession.
    /// - Returns: The authenticated user's GitLab profile.
    /// - Throws: `GitLabOAuthError` if authentication fails.
    func authenticate(
        instanceURL: URL,
        clientId: String,
        clientSecret: String? = nil,
        contextProvider: ASWebAuthenticationPresentationContextProviding
    ) async throws -> GitLabUser {
        // Validate instance URL
        guard let scheme = instanceURL.scheme,
              (scheme == "https" || scheme == "http"),
              instanceURL.host != nil else {
            throw GitLabOAuthError.invalidInstanceURL
        }

        // Generate PKCE code verifier and challenge
        let codeVerifier = generateCodeVerifier()
        let codeChallenge = generateCodeChallenge(from: codeVerifier)

        // Build authorization URL
        let authURL = buildAuthorizationURL(
            instanceURL: instanceURL,
            clientId: clientId,
            codeChallenge: codeChallenge
        )

        // Present ASWebAuthenticationSession on main actor
        let callbackURL = try await performWebAuthenticationOnMainActor(
            url: authURL,
            contextProvider: contextProvider
        )

        // Extract authorization code from callback
        let authorizationCode = try extractAuthorizationCode(from: callbackURL)

        // Exchange authorization code for tokens
        let tokenResponse = try await exchangeCodeForToken(
            instanceURL: instanceURL,
            clientId: clientId,
            clientSecret: clientSecret,
            code: authorizationCode,
            codeVerifier: codeVerifier
        )

        // Store tokens securely
        let tokenData = StoredTokenData(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(tokenResponse.createdAt) + TimeInterval(tokenResponse.expiresIn)),
            instanceURL: instanceURL.absoluteString,
            scope: tokenResponse.scope
        )
        try storeTokenData(tokenData)

        // Fetch and return user profile
        let user = try await fetchCurrentUser(
            instanceURL: instanceURL,
            accessToken: tokenResponse.accessToken
        )

        return user
    }

    // MARK: - PKCE Helpers

    /// Generates a cryptographically random code verifier for PKCE.
    private func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Generates a SHA-256 code challenge from the code verifier.
    private func generateCodeChallenge(from verifier: String) -> String {
        let data = Data(verifier.utf8)
        let hash = SHA256.hash(data: data)
        return Data(hash)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Builds the GitLab OAuth2 authorization URL with PKCE parameters.
    private func buildAuthorizationURL(
        instanceURL: URL,
        clientId: String,
        codeChallenge: String
    ) -> URL {
        var components = URLComponents(url: instanceURL.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: GitLabOAuthConfig.defaultRedirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GitLabOAuthConfig.defaultScopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        return components.url!
    }

    /// Presents ASWebAuthenticationSession on the main actor and returns the callback URL.
    private func performWebAuthenticationOnMainActor(
        url: URL,
        contextProvider: ASWebAuthenticationPresentationContextProviding
    ) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: GitLabOAuthConfig.callbackScheme
                ) { callbackURL, error in
                    if let error = error {
                        let nsError = error as NSError
                        if nsError.domain == ASWebAuthenticationSessionErrorDomain,
                           nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            continuation.resume(throwing: GitLabOAuthError.userCancelled)
                        } else {
                            continuation.resume(throwing: GitLabOAuthError.authenticationFailed(error.localizedDescription))
                        }
                        return
                    }

                    guard let callbackURL = callbackURL else {
                        continuation.resume(throwing: GitLabOAuthError.authenticationFailed("No callback URL received"))
                        return
                    }

                    continuation.resume(returning: callbackURL)
                }

                session.presentationContextProvider = contextProvider
                session.prefersEphemeralWebBrowserSession = false
                session.start()
            }
        }
    }

    /// Extracts the authorization code from the OAuth callback URL.
    private func extractAuthorizationCode(from url: URL) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            // Check for error in callback
            if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let error = components.queryItems?.first(where: { $0.name == "error" })?.value {
                let description = components.queryItems?.first(where: { $0.name == "error_description" })?.value ?? error
                throw GitLabOAuthError.authenticationFailed(description)
            }
            throw GitLabOAuthError.authenticationFailed("No authorization code in callback URL")
        }
        return code
    }

    // MARK: - Token Exchange

    /// Exchanges an authorization code for access and refresh tokens.
    private func exchangeCodeForToken(
        instanceURL: URL,
        clientId: String,
        clientSecret: String? = nil,
        code: String,
        codeVerifier: String
    ) async throws -> OAuthTokenResponse {
        let tokenURL = instanceURL.appendingPathComponent("oauth/token")

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params: [String: String] = [
            "client_id": clientId,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": GitLabOAuthConfig.defaultRedirectURI,
            "code_verifier": codeVerifier
        ]

        if let secret = clientSecret, !secret.isEmpty {
            params["client_secret"] = secret
        }

        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabOAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitLabOAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let decoder = JSONDecoder()
        do {
            return try decoder.decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw GitLabOAuthError.tokenExchangeFailed("Failed to decode token response: \(error.localizedDescription)")
        }
    }

    // MARK: - Token Refresh

    /// Refreshes the access token using the stored refresh token.
    /// - Returns: The new access token.
    /// - Throws: `GitLabOAuthError.tokenRefreshFailed` if refresh fails.
    func refreshToken() async throws -> String {
        guard !isRefreshing else {
            // Wait briefly and return cached token if another refresh is in progress
            try await Task.sleep(nanoseconds: 500_000_000)
            if let cached = cachedTokenData, cached.expiresAt > Date() {
                return cached.accessToken
            }
            throw GitLabOAuthError.tokenRefreshFailed("Concurrent refresh failed")
        }

        isRefreshing = true
        defer { isRefreshing = false }

        guard let tokenData = try loadTokenData() else {
            throw GitLabOAuthError.tokenNotFound
        }

        guard let instanceURL = URL(string: tokenData.instanceURL) else {
            throw GitLabOAuthError.invalidInstanceURL
        }

        // Load client ID
        let clientId: String
        do {
            clientId = try encryptionService.retrieveFromKeychain(key: KeychainKeys.clientId)
        } catch {
            throw GitLabOAuthError.tokenRefreshFailed("Client ID not found")
        }

        let tokenURL = instanceURL.appendingPathComponent("oauth/token")

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let params: [String: String] = [
            "client_id": clientId,
            "refresh_token": tokenData.refreshToken,
            "grant_type": "refresh_token",
            "redirect_uri": GitLabOAuthConfig.defaultRedirectURI
        ]

        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabOAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitLabOAuthError.tokenRefreshFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        let decoder = JSONDecoder()
        let tokenResponse: OAuthTokenResponse
        do {
            tokenResponse = try decoder.decode(OAuthTokenResponse.self, from: data)
        } catch {
            throw GitLabOAuthError.tokenRefreshFailed("Failed to decode refresh response: \(error.localizedDescription)")
        }

        // Store updated tokens
        let newTokenData = StoredTokenData(
            accessToken: tokenResponse.accessToken,
            refreshToken: tokenResponse.refreshToken,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(tokenResponse.createdAt) + TimeInterval(tokenResponse.expiresIn)),
            instanceURL: tokenData.instanceURL,
            scope: tokenResponse.scope
        )
        try storeTokenData(newTokenData)

        return tokenResponse.accessToken
    }

    // MARK: - Token Access

    /// Provides a valid access token, refreshing if expired.
    /// - Returns: A valid access token string.
    /// - Throws: `GitLabOAuthError` if no token is available or refresh fails.
    func getValidToken() async throws -> String {
        guard let tokenData = try loadTokenData() else {
            throw GitLabOAuthError.tokenNotFound
        }

        // Check if token is expired or about to expire (within 60 seconds)
        if tokenData.expiresAt.timeIntervalSinceNow < 60 {
            return try await refreshToken()
        }

        return tokenData.accessToken
    }

    /// Warms in-memory credential caches after app unlock so workspace changes do
    /// not trigger delayed Keychain prompts.
    func warmCredentialCache() {
        guard (try? loadTokenData()) != nil else {
            return
        }

        _ = try? encryptionService.retrieveFromKeychain(key: KeychainKeys.clientId)
    }

    /// Checks whether a valid token exists (not expired).
    func hasValidToken() -> Bool {
        guard let tokenData = try? loadTokenData() else {
            return false
        }
        return tokenData.expiresAt > Date()
    }

    /// Checks whether the stored token is expired.
    func isTokenExpired() -> Bool {
        guard let tokenData = try? loadTokenData() else {
            return true
        }
        return tokenData.expiresAt <= Date()
    }

    /// Returns the stored instance URL, if available.
    func getInstanceURL() -> URL? {
        guard let tokenData = try? loadTokenData(),
              let url = URL(string: tokenData.instanceURL) else {
            return nil
        }
        return url
    }

    // MARK: - Account Disconnection

    /// Disconnects the GitLab account by revoking the token and clearing local data.
    /// - Parameter showWarningOnRevocationFailure: Closure called if remote revocation fails.
    /// - Throws: Only throws if local cleanup fails (revocation failures are handled gracefully).
    func disconnect(onRevocationFailure: ((String) -> Void)? = nil) async throws {
        let tokenData = try? loadTokenData()

        // Attempt to revoke the token on GitLab
        if let tokenData = tokenData,
           let instanceURL = URL(string: tokenData.instanceURL) {
            do {
                try await revokeToken(
                    instanceURL: instanceURL,
                    token: tokenData.accessToken
                )
            } catch {
                // Graceful handling: clear local data anyway, but notify about revocation failure
                onRevocationFailure?("Remote token revocation failed: \(error.localizedDescription). Local data has been cleared.")
            }
        }

        // Always clear local data regardless of revocation success
        try clearLocalTokenData()
    }

    /// Revokes the token on the GitLab server.
    private func revokeToken(instanceURL: URL, token: String) async throws {
        let revokeURL = instanceURL.appendingPathComponent("oauth/revoke")

        var request = URLRequest(url: revokeURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        // Load client ID for revocation
        let clientId: String
        do {
            clientId = try encryptionService.retrieveFromKeychain(key: KeychainKeys.clientId)
        } catch {
            throw GitLabOAuthError.tokenRevocationFailed("Client ID not found for revocation")
        }

        let params: [String: String] = [
            "client_id": clientId,
            "token": token
        ]

        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (_, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabOAuthError.invalidResponse
        }

        // GitLab returns 200 on successful revocation
        guard httpResponse.statusCode == 200 else {
            throw GitLabOAuthError.tokenRevocationFailed("HTTP \(httpResponse.statusCode)")
        }
    }

    // MARK: - User Profile

    /// Fetches the current user's GitLab profile.
    private func fetchCurrentUser(instanceURL: URL, accessToken: String) async throws -> GitLabUser {
        let userURL = instanceURL.appendingPathComponent("api/v4/user")

        var request = URLRequest(url: userURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await performRequest(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitLabOAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw GitLabOAuthError.authenticationFailed("Failed to fetch user profile: HTTP \(httpResponse.statusCode) - \(errorBody)")
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(GitLabUser.self, from: data)
        } catch {
            throw GitLabOAuthError.authenticationFailed("Failed to decode user profile: \(error.localizedDescription)")
        }
    }

    /// Fetches the current user profile using the stored token.
    func fetchCurrentUserProfile() async throws -> GitLabUser {
        let token = try await getValidToken()
        guard let instanceURL = getInstanceURL() else {
            throw GitLabOAuthError.invalidInstanceURL
        }
        return try await fetchCurrentUser(instanceURL: instanceURL, accessToken: token)
    }

    // MARK: - Token Storage

    /// Stores token data encrypted in the Keychain.
    private func storeTokenData(_ tokenData: StoredTokenData) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(tokenData)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw GitLabOAuthError.tokenExchangeFailed("Failed to encode token data")
        }
        try encryptionService.storeInKeychain(key: KeychainKeys.tokenData, value: jsonString)
        cachedTokenData = tokenData
    }

    /// Loads token data from the Keychain (uses cache if available).
    private func loadTokenData() throws -> StoredTokenData? {
        if let cached = cachedTokenData {
            return cached
        }

        let jsonString: String
        do {
            jsonString = try encryptionService.retrieveFromKeychain(key: KeychainKeys.tokenData)
        } catch EncryptionError.keychainItemNotFound {
            return nil
        }

        guard let data = jsonString.data(using: .utf8) else {
            return nil
        }

        let decoder = JSONDecoder()
        let tokenData = try decoder.decode(StoredTokenData.self, from: data)
        cachedTokenData = tokenData
        return tokenData
    }

    /// Clears all locally stored token data.
    private func clearLocalTokenData() throws {
        try? encryptionService.deleteFromKeychain(key: KeychainKeys.tokenData)
        try? encryptionService.deleteFromKeychain(key: KeychainKeys.clientId)
        try? encryptionService.deleteFromKeychain(key: KeychainKeys.instanceURL)
        cachedTokenData = nil
    }

    /// Stores the client ID for later use in refresh/revocation.
    func storeClientId(_ clientId: String) throws {
        try encryptionService.storeInKeychain(key: KeychainKeys.clientId, value: clientId)
    }

    // MARK: - Network Helpers

    /// Performs a URL request with error handling.
    private func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error as URLError {
            throw GitLabOAuthError.networkError(error.localizedDescription)
        } catch {
            throw GitLabOAuthError.networkError(error.localizedDescription)
        }
    }
}
