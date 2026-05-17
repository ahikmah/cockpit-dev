import SwiftUI
import Combine

// MARK: - Window State Keys

/// UserDefaults keys for persisting window state.
enum WindowStateKeys {
    static let windowWidth = "cockpitdev.window.width"
    static let windowHeight = "cockpitdev.window.height"
    static let windowX = "cockpitdev.window.x"
    static let windowY = "cockpitdev.window.y"
    static let selectedWorkspaceId = "cockpitdev.selectedWorkspaceId"
    static let selectedTab = "cockpitdev.selectedTab"
    static let sidebarWidth = "cockpitdev.sidebar.width"
}

// MARK: - Window State

/// Represents the persisted state of the application window.
struct WindowState: Equatable {
    var width: CGFloat
    var height: CGFloat
    var x: CGFloat
    var y: CGFloat
    var selectedWorkspaceId: String?
    var selectedTab: String
    var sidebarWidth: CGFloat

    static let `default` = WindowState(
        width: 1200,
        height: 800,
        x: 100,
        y: 100,
        selectedWorkspaceId: nil,
        selectedTab: WorkspaceTab.board.rawValue,
        sidebarWidth: 240
    )
}

// MARK: - Window State Service

/// Manages persistence of window state (size, position, selected workspace, active tab)
/// using @AppStorage / UserDefaults for automatic restoration on app relaunch.
@Observable
class WindowStateService {

    // MARK: - Persisted Properties

    /// The last saved window width.
    var windowWidth: CGFloat {
        didSet { saveDebounced() }
    }

    /// The last saved window height.
    var windowHeight: CGFloat {
        didSet { saveDebounced() }
    }

    /// The last saved window X position.
    var windowX: CGFloat {
        didSet { saveDebounced() }
    }

    /// The last saved window Y position.
    var windowY: CGFloat {
        didSet { saveDebounced() }
    }

    /// The ID of the last selected workspace.
    var selectedWorkspaceId: String? {
        didSet { save() }
    }

    /// The last selected tab.
    var selectedTab: String {
        didSet { save() }
    }

    /// The sidebar width.
    var sidebarWidth: CGFloat {
        didSet { saveDebounced() }
    }

    // MARK: - Private

    private let defaults: UserDefaults
    private var saveTask: Task<Void, Never>?

    // MARK: - Initialization

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Load persisted state
        self.windowWidth = defaults.double(forKey: WindowStateKeys.windowWidth).nonZeroOr(WindowState.default.width)
        self.windowHeight = defaults.double(forKey: WindowStateKeys.windowHeight).nonZeroOr(WindowState.default.height)
        self.windowX = defaults.double(forKey: WindowStateKeys.windowX).nonZeroOr(WindowState.default.x)
        self.windowY = defaults.double(forKey: WindowStateKeys.windowY).nonZeroOr(WindowState.default.y)
        self.selectedWorkspaceId = defaults.string(forKey: WindowStateKeys.selectedWorkspaceId)
        self.selectedTab = defaults.string(forKey: WindowStateKeys.selectedTab) ?? WindowState.default.selectedTab
        self.sidebarWidth = defaults.double(forKey: WindowStateKeys.sidebarWidth).nonZeroOr(WindowState.default.sidebarWidth)
    }

    // MARK: - Public Methods

    /// Returns the current window state as a struct.
    var currentState: WindowState {
        WindowState(
            width: windowWidth,
            height: windowHeight,
            x: windowX,
            y: windowY,
            selectedWorkspaceId: selectedWorkspaceId,
            selectedTab: selectedTab,
            sidebarWidth: sidebarWidth
        )
    }

    /// Updates the window frame from an NSWindow frame.
    func updateWindowFrame(origin: CGPoint, size: CGSize) {
        windowX = origin.x
        windowY = origin.y
        windowWidth = size.width
        windowHeight = size.height
    }

    /// Updates the selected workspace.
    func selectWorkspace(id: UUID?) {
        selectedWorkspaceId = id?.uuidString
    }

    /// Updates the selected tab.
    func selectTab(_ tab: WorkspaceTab) {
        selectedTab = tab.rawValue
    }

    /// Returns the persisted tab selection.
    var restoredTab: WorkspaceTab {
        WorkspaceTab(rawValue: selectedTab) ?? .board
    }

    /// Returns the persisted workspace ID.
    var restoredWorkspaceId: UUID? {
        guard let idString = selectedWorkspaceId else { return nil }
        return UUID(uuidString: idString)
    }

    // MARK: - Persistence

    /// Saves state immediately.
    func save() {
        defaults.set(windowWidth, forKey: WindowStateKeys.windowWidth)
        defaults.set(windowHeight, forKey: WindowStateKeys.windowHeight)
        defaults.set(windowX, forKey: WindowStateKeys.windowX)
        defaults.set(windowY, forKey: WindowStateKeys.windowY)
        defaults.set(selectedWorkspaceId, forKey: WindowStateKeys.selectedWorkspaceId)
        defaults.set(selectedTab, forKey: WindowStateKeys.selectedTab)
        defaults.set(sidebarWidth, forKey: WindowStateKeys.sidebarWidth)
    }

    /// Debounced save for frequent updates (window resize/move).
    private func saveDebounced() {
        saveTask?.cancel()
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
            guard !Task.isCancelled else { return }
            self.save()
        }
    }

    /// Resets all persisted state to defaults.
    func resetToDefaults() {
        let state = WindowState.default
        windowWidth = state.width
        windowHeight = state.height
        windowX = state.x
        windowY = state.y
        selectedWorkspaceId = state.selectedWorkspaceId
        selectedTab = state.selectedTab
        sidebarWidth = state.sidebarWidth
        save()
    }
}

// MARK: - Window State View Modifier

/// A view modifier that persists window state changes.
struct WindowStatePersistence: ViewModifier {

    let windowStateService: WindowStateService

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { notification in
                guard let window = notification.object as? NSWindow else { return }
                windowStateService.updateWindowFrame(origin: window.frame.origin, size: window.frame.size)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notification in
                guard let window = notification.object as? NSWindow else { return }
                windowStateService.updateWindowFrame(origin: window.frame.origin, size: window.frame.size)
            }
    }
}

extension View {
    /// Adds window state persistence to the view.
    func persistWindowState(using service: WindowStateService) -> some View {
        modifier(WindowStatePersistence(windowStateService: service))
    }
}

// MARK: - Double Extension

private extension Double {
    /// Returns self if non-zero, otherwise returns the fallback value.
    func nonZeroOr(_ fallback: CGFloat) -> CGFloat {
        self != 0 ? CGFloat(self) : fallback
    }
}
