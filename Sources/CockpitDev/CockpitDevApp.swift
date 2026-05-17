import SwiftUI
import SwiftData

@main
struct CockpitDevApp: App {

    /// The SwiftData model container configured with all model types.
    let modelContainer: ModelContainer

    /// The authentication service managing app-level auth state.
    @State private var authService = AuthenticationService()

    /// The window state service for persisting window size, position, and selections.
    @State private var windowStateService = WindowStateService()

    /// Keyboard shortcut state for handling app-wide shortcuts.
    @State private var shortcutState = KeyboardShortcutState()

    init() {
        do {
            let schema = Schema([
                Workspace.self,
                Repository.self,
                Member.self,
                Ticket.self,
                Sprint.self,
                MergeRequestEntry.self,
                Document.self,
                OpenSpecEntry.self,
                DocSpecVersion.self,
                AppNotification.self
            ])

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView(authService: authService)
                .environment(windowStateService)
                .environment(shortcutState)
                .persistWindowState(using: windowStateService)
        }
        .modelContainer(modelContainer)
        .defaultSize(
            width: windowStateService.windowWidth,
            height: windowStateService.windowHeight
        )
        .commands {
            CockpitDevCommands(
                showCreateWorkspace: $shortcutState.showCreateWorkspace,
                triggerRefresh: $shortcutState.triggerRefresh,
                showCreateTicket: $shortcutState.showCreateTicket,
                showNotifications: $shortcutState.showNotifications,
                showSearch: $shortcutState.showSearch,
                showSettings: $shortcutState.showSettings
            )
        }
    }
}
