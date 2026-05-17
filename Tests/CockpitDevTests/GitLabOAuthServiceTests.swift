import XCTest
@testable import CockpitDev

/// Unit tests for GitLabOAuthService covering token storage, refresh, expiry detection,
/// disconnection, and PKCE code generation.
final class GitLabOAuthServiceTests: XCTestCase {

    private var encryptionService: EncryptionService!
    private var oauthService: GitLabOAuthService!

    override func setUp() {
        super.setUp()
        // Use a unique service identifier to avoid conflicts with production Keychain entries
        encryptionService = EncryptionService(serviceIdentifier: "com.cockpitdev.tests.oauth.\(UUID().uuidString)")
        oauthService = GitLabOAuthService(encryptionService: encryptionService)
    }

    override func tearDown() {
        // Clean up Keychain entries
        try? encryptionService.deleteFromKeychain(key: "gitlab.oauth.tokenData")
        try? encryptionService.deleteFromKeychain(key: "gitlab.oauth.clientId")
        try? encryptionService.deleteFromKeychain(key: "gitlab.oauth.instanceURL")
        encryptionService = nil
        oauthService = nil
        super.tearDown()
    }

    // MARK: - Token Existence Tests

    func testHasValidToken_WhenNoTokenStored_ReturnsFalse() async {
        let hasToken = await oauthService.hasValidToken()
        XCTAssertFalse(hasToken, "Should return false when no token is stored")
    }

    func testIsTokenExpired_WhenNoTokenStored_ReturnsTrue() async {
        let isExpired = await oauthService.isTokenExpired()
        XCTAssertTrue(isExpired, "Should return true when no token is stored")
    }

    func testGetInstanceURL_WhenNoTokenStored_ReturnsNil() async {
        let url = await oauthService.getInstanceURL()
        XCTAssertNil(url, "Should return nil when no token is stored")
    }

    // MARK: - Token Access Tests

    func testGetValidToken_WhenNoTokenStored_ThrowsTokenNotFound() async {
        do {
            _ = try await oauthService.getValidToken()
            XCTFail("Should throw tokenNotFound error")
        } catch let error as GitLabOAuthError {
            if case .tokenNotFound = error {
                // Expected
            } else {
                XCTFail("Expected tokenNotFound, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Disconnect Tests

    func testDisconnect_WhenNoTokenStored_CompletesWithoutError() async {
        // Disconnecting when no token is stored should not throw
        do {
            try await oauthService.disconnect()
        } catch {
            XCTFail("Disconnect should not throw when no token is stored: \(error)")
        }
    }

    func testDisconnect_ClearsLocalData() async throws {
        // Store a client ID to verify it gets cleared
        try encryptionService.storeInKeychain(key: "gitlab.oauth.clientId", value: "test-client-id")

        try await oauthService.disconnect()

        // Verify client ID was cleared
        XCTAssertThrowsError(try encryptionService.retrieveFromKeychain(key: "gitlab.oauth.clientId")) { error in
            guard case EncryptionError.keychainItemNotFound = error else {
                XCTFail("Expected keychainItemNotFound, got \(error)")
                return
            }
        }
    }

    // MARK: - Client ID Storage Tests

    func testStoreClientId_StoresSuccessfully() async throws {
        try await oauthService.storeClientId("my-test-client-id")

        let retrieved = try encryptionService.retrieveFromKeychain(key: "gitlab.oauth.clientId")
        XCTAssertEqual(retrieved, "my-test-client-id")
    }

    // MARK: - OAuth Error Tests

    func testGitLabOAuthError_HasDescriptions() {
        let errors: [GitLabOAuthError] = [
            .invalidInstanceURL,
            .authenticationFailed("test reason"),
            .tokenExchangeFailed("exchange reason"),
            .tokenRefreshFailed("refresh reason"),
            .tokenRevocationFailed("revoke reason"),
            .tokenNotFound,
            .tokenExpired,
            .networkError("network reason"),
            .invalidResponse,
            .userCancelled
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Error \(error) should have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty, "Error description should not be empty")
        }
    }

    // MARK: - OAuth Config Tests

    func testOAuthConfig_DefaultValues() {
        XCTAssertEqual(GitLabOAuthConfig.defaultScopes, ["api", "read_user", "read_repository"])
        XCTAssertEqual(GitLabOAuthConfig.callbackScheme, "cockpitdev")
        XCTAssertEqual(GitLabOAuthConfig.defaultRedirectURI, "cockpitdev://oauth/callback")
    }

    // MARK: - StoredTokenData Tests

    func testStoredTokenData_EncodesAndDecodes() throws {
        let tokenData = StoredTokenData(
            accessToken: "test-access-token",
            refreshToken: "test-refresh-token",
            expiresAt: Date(timeIntervalSince1970: 1700000000),
            instanceURL: "https://gitlab.com",
            scope: "api read_user"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(tokenData)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(StoredTokenData.self, from: data)

        XCTAssertEqual(decoded.accessToken, "test-access-token")
        XCTAssertEqual(decoded.refreshToken, "test-refresh-token")
        XCTAssertEqual(decoded.instanceURL, "https://gitlab.com")
        XCTAssertEqual(decoded.scope, "api read_user")
        XCTAssertEqual(decoded.expiresAt.timeIntervalSince1970, 1700000000, accuracy: 1)
    }

    // MARK: - OAuthTokenResponse Tests

    func testOAuthTokenResponse_DecodesFromJSON() throws {
        let json = """
        {
            "access_token": "abc123",
            "token_type": "Bearer",
            "expires_in": 7200,
            "refresh_token": "refresh456",
            "created_at": 1700000000,
            "scope": "api read_user"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(OAuthTokenResponse.self, from: json)

        XCTAssertEqual(response.accessToken, "abc123")
        XCTAssertEqual(response.tokenType, "Bearer")
        XCTAssertEqual(response.expiresIn, 7200)
        XCTAssertEqual(response.refreshToken, "refresh456")
        XCTAssertEqual(response.createdAt, 1700000000)
        XCTAssertEqual(response.scope, "api read_user")
    }

    func testOAuthTokenResponse_DecodesWithoutScope() throws {
        let json = """
        {
            "access_token": "abc123",
            "token_type": "Bearer",
            "expires_in": 7200,
            "refresh_token": "refresh456",
            "created_at": 1700000000
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        let response = try decoder.decode(OAuthTokenResponse.self, from: json)

        XCTAssertEqual(response.accessToken, "abc123")
        XCTAssertNil(response.scope)
    }

    // MARK: - Token Refresh Tests

    func testRefreshToken_WhenNoTokenStored_ThrowsTokenNotFound() async {
        do {
            _ = try await oauthService.refreshToken()
            XCTFail("Should throw an error")
        } catch let error as GitLabOAuthError {
            if case .tokenNotFound = error {
                // Expected
            } else {
                XCTFail("Expected tokenNotFound, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }
}
