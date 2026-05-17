import SwiftUI
import AuthenticationServices

// MARK: - GitLabConnectSheet

/// A sheet view for connecting/disconnecting a GitLab account.
/// Provides instance URL input, OAuth client ID input, connect button,
/// and displays the connected user's profile after successful authentication.
struct GitLabConnectSheet: View {

    // MARK: - Properties

    @Bindable var viewModel: GitLabOAuthViewModel
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            // Header
            headerView

            Divider()

            // Content based on connection state
            switch viewModel.connectionState {
            case .disconnected, .error, .needsReauthentication:
                connectionFormView
            case .connecting:
                connectingView
            case .connected:
                connectedProfileView
            }

            Spacer()

            // Footer actions
            footerView
        }
        .padding(24)
        .frame(minWidth: 480, maxWidth: 480, minHeight: 400)
        .task {
            await viewModel.checkConnectionStatus()
        }
        .alert("Disconnection Warning", isPresented: $viewModel.showDisconnectWarning) {
            Button("OK") {
                viewModel.showDisconnectWarning = false
            }
        } message: {
            Text(viewModel.revocationWarningMessage ?? "Token revocation failed, but local data has been cleared.")
        }
        .confirmationDialog(
            "Disconnect GitLab Account",
            isPresented: $viewModel.showDisconnectConfirmation,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive) {
                Task {
                    await viewModel.disconnect()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will revoke your access token and remove all cached GitLab data. You will need to re-authenticate to use GitLab features.")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "network")
                .font(.system(size: 24))
                .foregroundStyle(.indigo)

            VStack(alignment: .leading, spacing: 4) {
                Text("GitLab Account")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))

                Text("Connect your GitLab account to sync projects and data.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Connection Form

    private var connectionFormView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Error message
            if case .error(let message) = viewModel.connectionState {
                errorBanner(message: message)
            }

            // Re-auth prompt
            if case .needsReauthentication = viewModel.connectionState {
                reauthBanner
            }

            // Instance URL field
            VStack(alignment: .leading, spacing: 6) {
                Text("GitLab Instance URL")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("https://gitlab.com", text: $viewModel.instanceURLString)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .accessibilityLabel("GitLab instance URL")

                if !viewModel.instanceURLString.isEmpty && !viewModel.isInstanceURLValid {
                    Text("Please enter a valid URL (e.g., https://gitlab.com)")
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
            }

            // Client ID field
            VStack(alignment: .leading, spacing: 6) {
                Text("OAuth Application Client ID")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("Your GitLab OAuth application client ID", text: $viewModel.clientId)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .accessibilityLabel("OAuth client ID")
            }

            // Client Secret field
            VStack(alignment: .leading, spacing: 6) {
                Text("OAuth Application Client Secret")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                SecureField("Your GitLab OAuth application secret", text: $viewModel.clientSecret)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .accessibilityLabel("OAuth client secret")

                Text("Required for confidential applications or older GitLab versions.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            // Instructions
            VStack(alignment: .leading, spacing: 4) {
                Text("Create an OAuth application in GitLab → Settings → Applications with redirect URI: cockpitdev://oauth/callback")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            // Connect button
            HStack {
                Spacer()
                Button(action: {
                    Task {
                        let provider = WebAuthContextProvider()
                        await viewModel.connect(contextProvider: provider)
                    }
                }) {
                    Label("Connect to GitLab", systemImage: "link")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(!viewModel.canConnect)
                .accessibilityLabel("Connect to GitLab")
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Connecting State

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Authenticating with GitLab...")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Text("A browser window will open for you to authorize Cockpit Dev.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Connected Profile

    private var connectedProfileView: some View {
        VStack(spacing: 16) {
            // Profile card
            if let user = viewModel.connectedUser {
                HStack(spacing: 16) {
                    // Avatar
                    AsyncImage(url: URL(string: user.avatarUrl ?? "")) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Image(systemName: "person.circle.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())

                    // User info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.name)
                            .font(.system(size: 15, weight: .semibold))

                        Text("@\(user.username)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)

                        if let email = user.email {
                            Text(email)
                                .font(.system(size: 12))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    Spacer()

                    // Connected badge
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                        )
                )
            }

            // Instance URL display
            if case .connected = viewModel.connectionState {
                HStack {
                    Text("Instance:")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(viewModel.instanceURLString)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                    Spacer()
                }
            }

            // Disconnect button
            HStack {
                Spacer()
                Button(role: .destructive) {
                    viewModel.showDisconnectConfirmation = true
                } label: {
                    Label("Disconnect Account", systemImage: "link.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                }
                .accessibilityLabel("Disconnect GitLab account")
                Spacer()
            }
            .padding(.top, 8)
        }
    }

    // MARK: - Error Banner

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Re-auth Banner

    private var reauthBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.clockwise.circle.fill")
                .foregroundStyle(.orange)

            Text("Your session has expired. Please re-authenticate to continue using GitLab features.")
                .font(.system(size: 12))
                .foregroundStyle(.primary)

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack {
            Button("Close") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)

            Spacer()
        }
    }
}

// MARK: - WebAuthContextProvider

/// Provides the presentation context for ASWebAuthenticationSession on macOS.
class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}
