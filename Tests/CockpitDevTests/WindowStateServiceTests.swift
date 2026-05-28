import XCTest
@testable import CockpitDev

/// Unit tests for WindowStateService persistence and restoration.
final class WindowStateServiceTests: CockpitDevTestCase {

    private var defaults: UserDefaults!
    private var service: WindowStateService!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        // Use a unique suite name to avoid polluting real UserDefaults
        suiteName = "com.cockpitdev.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        service = WindowStateService(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        service = nil
        suiteName = nil
        super.tearDown()
    }

    // MARK: - Default Values

    func testDefaultValues() {
        XCTAssertEqual(service.windowWidth, WindowState.default.width)
        XCTAssertEqual(service.windowHeight, WindowState.default.height)
        XCTAssertEqual(service.windowX, WindowState.default.x)
        XCTAssertEqual(service.windowY, WindowState.default.y)
        XCTAssertNil(service.selectedWorkspaceId)
        XCTAssertEqual(service.selectedTab, WorkspaceTab.board.rawValue)
        XCTAssertEqual(service.sidebarWidth, WindowState.default.sidebarWidth)
    }

    // MARK: - Window Frame Persistence

    func testUpdateWindowFrame() {
        service.updateWindowFrame(origin: CGPoint(x: 200, y: 300), size: CGSize(width: 1400, height: 900))
        service.save()

        XCTAssertEqual(service.windowX, 200)
        XCTAssertEqual(service.windowY, 300)
        XCTAssertEqual(service.windowWidth, 1400)
        XCTAssertEqual(service.windowHeight, 900)

        // Verify persistence
        let restored = WindowStateService(defaults: defaults)
        XCTAssertEqual(restored.windowX, 200)
        XCTAssertEqual(restored.windowY, 300)
        XCTAssertEqual(restored.windowWidth, 1400)
        XCTAssertEqual(restored.windowHeight, 900)
    }

    // MARK: - Workspace Selection Persistence

    func testSelectWorkspace() {
        let workspaceId = UUID()
        service.selectWorkspace(id: workspaceId)
        service.save()

        XCTAssertEqual(service.selectedWorkspaceId, workspaceId.uuidString)
        XCTAssertEqual(service.restoredWorkspaceId, workspaceId)

        // Verify persistence
        let restored = WindowStateService(defaults: defaults)
        XCTAssertEqual(restored.restoredWorkspaceId, workspaceId)
    }

    func testSelectWorkspaceNil() {
        service.selectWorkspace(id: nil)
        service.save()

        XCTAssertNil(service.selectedWorkspaceId)
        XCTAssertNil(service.restoredWorkspaceId)
    }

    // MARK: - Tab Selection Persistence

    func testSelectTab() {
        service.selectTab(.analytics)
        service.save()

        XCTAssertEqual(service.selectedTab, WorkspaceTab.analytics.rawValue)
        XCTAssertEqual(service.restoredTab, .analytics)

        // Verify persistence
        let restored = WindowStateService(defaults: defaults)
        XCTAssertEqual(restored.restoredTab, .analytics)
    }

    func testSelectTabAllValues() {
        for tab in WorkspaceTab.allCases {
            service.selectTab(tab)
            XCTAssertEqual(service.restoredTab, tab)
        }
    }

    // MARK: - Sidebar Width Persistence

    func testSidebarWidth() {
        service.sidebarWidth = 280
        service.save()

        let restored = WindowStateService(defaults: defaults)
        XCTAssertEqual(restored.sidebarWidth, 280)
    }

    // MARK: - Reset to Defaults

    func testResetToDefaults() {
        // Set custom values
        service.updateWindowFrame(origin: CGPoint(x: 500, y: 600), size: CGSize(width: 1600, height: 1000))
        service.selectWorkspace(id: UUID())
        service.selectTab(.settings)
        service.sidebarWidth = 300
        service.save()

        // Reset
        service.resetToDefaults()

        XCTAssertEqual(service.windowWidth, WindowState.default.width)
        XCTAssertEqual(service.windowHeight, WindowState.default.height)
        XCTAssertEqual(service.windowX, WindowState.default.x)
        XCTAssertEqual(service.windowY, WindowState.default.y)
        XCTAssertNil(service.selectedWorkspaceId)
        XCTAssertEqual(service.selectedTab, WorkspaceTab.board.rawValue)
        XCTAssertEqual(service.sidebarWidth, WindowState.default.sidebarWidth)
    }

    // MARK: - Current State

    func testCurrentState() {
        service.updateWindowFrame(origin: CGPoint(x: 150, y: 250), size: CGSize(width: 1300, height: 850))
        service.selectTab(.sprints)

        let state = service.currentState
        XCTAssertEqual(state.width, 1300)
        XCTAssertEqual(state.height, 850)
        XCTAssertEqual(state.x, 150)
        XCTAssertEqual(state.y, 250)
        XCTAssertEqual(state.selectedTab, WorkspaceTab.sprints.rawValue)
    }

    // MARK: - Edge Cases

    func testRestoredTabWithInvalidValue() {
        // Manually set an invalid tab value
        defaults.set("InvalidTab", forKey: WindowStateKeys.selectedTab)

        let restored = WindowStateService(defaults: defaults)
        XCTAssertEqual(restored.restoredTab, .board) // Falls back to default
    }

    func testRestoredWorkspaceIdWithInvalidUUID() {
        defaults.set("not-a-uuid", forKey: WindowStateKeys.selectedWorkspaceId)

        let restored = WindowStateService(defaults: defaults)
        XCTAssertNil(restored.restoredWorkspaceId)
    }
}
