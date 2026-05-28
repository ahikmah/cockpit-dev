import SwiftUI

/// Shared credential-related services for the app lifetime.
///
/// Keeping these services app-scoped avoids repeated Keychain construction and
/// repeated credential reads while moving between workspaces and settings panes.
struct CredentialServices {
    let encryptionService: EncryptionService
    let gitLabOAuthService: GitLabOAuthService

    init(encryptionService: EncryptionService = EncryptionService()) {
        self.encryptionService = encryptionService
        self.gitLabOAuthService = GitLabOAuthService(encryptionService: encryptionService)
    }
}

private struct CredentialServicesKey: EnvironmentKey {
    static let defaultValue = CredentialServices()
}

extension EnvironmentValues {
    var credentialServices: CredentialServices {
        get { self[CredentialServicesKey.self] }
        set { self[CredentialServicesKey.self] = newValue }
    }
}
