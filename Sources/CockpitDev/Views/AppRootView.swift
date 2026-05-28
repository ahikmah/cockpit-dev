import SwiftUI

/// Root view that manages the transition between LockScreen and MainWindow.
/// Requires authentication on launch and shows no workspace data until authenticated.
struct AppRootView: View {

    @Environment(\.credentialServices) private var credentialServices
    @Bindable var authService: AuthenticationService

    var body: some View {
        Group {
            if authService.isAuthenticated {
                MainWindowView()
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                LockScreenView(authService: authService)
                    .transition(.opacity)
            }
        }
        .animation(
            .spring(response: 0.35, dampingFraction: 0.85),
            value: authService.isAuthenticated
        )
        .task(id: authService.isAuthenticated) {
            guard authService.isAuthenticated else { return }
            await credentialServices.gitLabOAuthService.warmCredentialCache()
        }
        .activateContainingWindow()
    }
}

#Preview("Authenticated") {
    let service = AuthenticationService()
    service.recordSuccess()
    return AppRootView(authService: service)
        .frame(width: 900, height: 600)
}

#Preview("Locked") {
    AppRootView(authService: AuthenticationService())
        .frame(width: 500, height: 400)
}
