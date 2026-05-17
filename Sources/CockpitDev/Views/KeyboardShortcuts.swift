import SwiftUI

// MARK: - Keyboard Shortcut Commands

/// Defines the app's keyboard shortcuts using SwiftUI's Commands API.
/// These are added to the app's menu bar and respond to key combinations.
struct CockpitDevCommands: Commands {

    /// Binding to trigger new workspace creation.
    @Binding var showCreateWorkspace: Bool

    /// Binding to trigger refresh action.
    @Binding var triggerRefresh: Bool

    /// Binding to trigger new ticket creation.
    @Binding var showCreateTicket: Bool

    /// Binding to trigger notification center.
    @Binding var showNotifications: Bool

    /// Binding to trigger search.
    @Binding var showSearch: Bool

    /// Binding to trigger settings.
    @Binding var showSettings: Bool

    var body: some Commands {
        // File menu shortcuts
        CommandGroup(after: .newItem) {
            Button("New Workspace") {
                showCreateWorkspace = true
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("New Ticket") {
                showCreateTicket = true
            }
            .keyboardShortcut("n", modifiers: [.command])

            Divider()
        }

        // View menu shortcuts
        CommandGroup(after: .toolbar) {
            Button("Refresh") {
                triggerRefresh = true
            }
            .keyboardShortcut("r", modifiers: [.command])

            Divider()
        }

        // Window menu shortcuts
        CommandGroup(after: .windowArrangement) {
            Button("Notifications") {
                showNotifications = true
            }
            .keyboardShortcut("n", modifiers: [.command, .option])

            Button("Search") {
                showSearch = true
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Settings") {
                showSettings = true
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()
        }
    }
}

// MARK: - Keyboard Shortcut State

/// Observable state object that manages keyboard shortcut triggers.
/// Used by the app to respond to keyboard shortcut activations.
@Observable
class KeyboardShortcutState {
    var showCreateWorkspace: Bool = false
    var triggerRefresh: Bool = false
    var showCreateTicket: Bool = false
    var showNotifications: Bool = false
    var showSearch: Bool = false
    var showSettings: Bool = false

    /// Resets all triggers after they've been handled.
    func resetRefreshTrigger() {
        triggerRefresh = false
    }
}

// MARK: - Keyboard Shortcut Modifier

/// A view modifier that adds keyboard shortcut handling to any view.
/// Listens for shortcut state changes and triggers appropriate actions.
struct KeyboardShortcutHandler: ViewModifier {

    @Bindable var shortcutState: KeyboardShortcutState

    var onCreateWorkspace: (() -> Void)?
    var onCreateTicket: (() -> Void)?
    var onRefresh: (() -> Void)?
    var onShowNotifications: (() -> Void)?
    var onSearch: (() -> Void)?
    var onShowSettings: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onChange(of: shortcutState.showCreateWorkspace) { _, newValue in
                if newValue {
                    onCreateWorkspace?()
                    shortcutState.showCreateWorkspace = false
                }
            }
            .onChange(of: shortcutState.showCreateTicket) { _, newValue in
                if newValue {
                    onCreateTicket?()
                    shortcutState.showCreateTicket = false
                }
            }
            .onChange(of: shortcutState.triggerRefresh) { _, newValue in
                if newValue {
                    onRefresh?()
                    shortcutState.resetRefreshTrigger()
                }
            }
            .onChange(of: shortcutState.showNotifications) { _, newValue in
                if newValue {
                    onShowNotifications?()
                    shortcutState.showNotifications = false
                }
            }
            .onChange(of: shortcutState.showSearch) { _, newValue in
                if newValue {
                    onSearch?()
                    shortcutState.showSearch = false
                }
            }
            .onChange(of: shortcutState.showSettings) { _, newValue in
                if newValue {
                    onShowSettings?()
                    shortcutState.showSettings = false
                }
            }
    }
}

extension View {
    /// Adds keyboard shortcut handling to the view.
    func handleKeyboardShortcuts(
        state: KeyboardShortcutState,
        onCreateWorkspace: (() -> Void)? = nil,
        onCreateTicket: (() -> Void)? = nil,
        onRefresh: (() -> Void)? = nil,
        onShowNotifications: (() -> Void)? = nil,
        onSearch: (() -> Void)? = nil,
        onShowSettings: (() -> Void)? = nil
    ) -> some View {
        modifier(KeyboardShortcutHandler(
            shortcutState: state,
            onCreateWorkspace: onCreateWorkspace,
            onCreateTicket: onCreateTicket,
            onRefresh: onRefresh,
            onShowNotifications: onShowNotifications,
            onSearch: onSearch,
            onShowSettings: onShowSettings
        ))
    }
}
