import XCTest
import SwiftData
@testable import CockpitDev

final class NotificationServiceTests: CockpitDevTestCase {

    private var service: NotificationService!
    private var modelContainer: ModelContainer!
    private var modelContext: ModelContext!
    private var workspace: Workspace!

    @MainActor
    override func setUp() {
        super.setUp()
        // Use nil notification center to avoid UNUserNotificationCenter crash in test environment
        service = NotificationService(notificationCenter: nil)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try! ModelContainer(
            for: Workspace.self, AppNotification.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext

        workspace = Workspace(name: "Test Workspace")
        modelContext.insert(workspace)
        try! modelContext.save()

        service.configure(with: modelContext)
    }

    override func tearDown() {
        service = nil
        modelContainer = nil
        modelContext = nil
        workspace = nil
        super.tearDown()
    }

    // MARK: - Permission Tests

    func testInitialPermissionStatusIsNotDetermined() {
        XCTAssertEqual(service.permissionStatus, .notDetermined)
        XCTAssertFalse(service.isPermissionDenied)
    }

    // MARK: - Notification Delivery Tests

    @MainActor
    func testDeliverCreatesInAppNotification() async {
        await service.deliver(
            event: .newMergeRequest,
            title: "New MR",
            message: "Feature branch ready for review",
            workspace: workspace,
            relatedItemId: UUID(),
            relatedItemType: "MergeRequest"
        )

        let notifications = service.getNotifications(workspace: workspace)
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(notifications.first?.title, "New MR")
        XCTAssertEqual(notifications.first?.message, "Feature branch ready for review")
        XCTAssertEqual(notifications.first?.eventType, .newMergeRequest)
        XCTAssertFalse(notifications.first?.isRead ?? true)
    }

    @MainActor
    func testDeliverRespectsDisabledNotificationType() async {
        // Disable newMergeRequest notifications
        service.setEnabled(.newMergeRequest, enabled: false, workspace: workspace)

        await service.deliver(
            event: .newMergeRequest,
            title: "New MR",
            message: "Should not be delivered",
            workspace: workspace
        )

        let notifications = service.getNotifications(workspace: workspace)
        XCTAssertEqual(notifications.count, 0)
    }

    @MainActor
    func testDeliverAllowsEnabledNotificationType() async {
        // Explicitly enable
        service.setEnabled(.dependencyConflict, enabled: true, workspace: workspace)

        await service.deliver(
            event: .dependencyConflict,
            title: "Conflict",
            message: "Dependency conflict detected",
            workspace: workspace
        )

        let notifications = service.getNotifications(workspace: workspace)
        XCTAssertEqual(notifications.count, 1)
    }

    // MARK: - Notification Cap (Property 6) Tests

    @MainActor
    func testNotificationCapEvictsOldest() async {
        // Persist incrementally, matching production delivery behavior and avoiding
        // a large graph of temporary SwiftData relationship identifiers.
        for i in 0..<500 {
            let notification = AppNotification(
                eventType: .newMergeRequest,
                title: "MR #\(i)",
                message: "Message \(i)",
                createdAt: Date().addingTimeInterval(TimeInterval(i))
            )
            notification.workspace = workspace
            modelContext.insert(notification)
            try! modelContext.save()
        }

        XCTAssertEqual(workspace.notifications.count, 500)

        // Deliver one more notification (should evict the oldest)
        await service.deliver(
            event: .mrApproval,
            title: "New Notification",
            message: "This should trigger eviction",
            workspace: workspace
        )

        XCTAssertLessThanOrEqual(workspace.notifications.count, AppConstants.maxNotifications)
    }

    @MainActor
    func testNotificationCapDoesNotEvictWhenUnderLimit() async {
        // Insert 10 notifications
        for i in 0..<10 {
            let notification = AppNotification(
                eventType: .newMergeRequest,
                title: "MR #\(i)",
                message: "Message \(i)"
            )
            notification.workspace = workspace
            modelContext.insert(notification)
        }
        try! modelContext.save()

        await service.deliver(
            event: .mrApproval,
            title: "Another",
            message: "No eviction needed",
            workspace: workspace
        )

        XCTAssertEqual(workspace.notifications.count, 11)
    }

    // MARK: - Mark As Read Tests

    @MainActor
    func testMarkAsRead() async {
        await service.deliver(
            event: .newMergeRequest,
            title: "Test",
            message: "Test message",
            workspace: workspace
        )

        let notifications = service.getNotifications(workspace: workspace)
        XCTAssertFalse(notifications.first!.isRead)

        service.markAsRead(notifications.first!)
        XCTAssertTrue(notifications.first!.isRead)
    }

    @MainActor
    func testMarkAllAsRead() async {
        for i in 0..<5 {
            await service.deliver(
                event: .newMergeRequest,
                title: "MR #\(i)",
                message: "Message",
                workspace: workspace
            )
        }

        XCTAssertEqual(service.unreadCount(workspace: workspace), 5)

        service.markAllAsRead(workspace: workspace)
        XCTAssertEqual(service.unreadCount(workspace: workspace), 0)
    }

    // MARK: - Unread Count Tests

    @MainActor
    func testUnreadCount() async {
        await service.deliver(
            event: .newMergeRequest,
            title: "MR 1",
            message: "Message",
            workspace: workspace
        )
        await service.deliver(
            event: .mrApproval,
            title: "MR 2",
            message: "Message",
            workspace: workspace
        )

        XCTAssertEqual(service.unreadCount(workspace: workspace), 2)

        let notifications = service.getNotifications(workspace: workspace)
        service.markAsRead(notifications.first!)

        XCTAssertEqual(service.unreadCount(workspace: workspace), 1)
    }

    // MARK: - Per-Workspace Configuration Tests

    @MainActor
    func testAllNotificationTypesEnabledByDefault() {
        for eventType in NotificationEventType.allCases {
            XCTAssertTrue(service.isEnabled(eventType, workspace: workspace))
        }
    }

    @MainActor
    func testSetEnabledPersistsConfiguration() {
        service.setEnabled(.newMergeRequest, enabled: false, workspace: workspace)
        XCTAssertFalse(service.isEnabled(.newMergeRequest, workspace: workspace))

        service.setEnabled(.newMergeRequest, enabled: true, workspace: workspace)
        XCTAssertTrue(service.isEnabled(.newMergeRequest, workspace: workspace))
    }

    @MainActor
    func testDisablingOneTypeDoesNotAffectOthers() {
        service.setEnabled(.newMergeRequest, enabled: false, workspace: workspace)

        XCTAssertFalse(service.isEnabled(.newMergeRequest, workspace: workspace))
        XCTAssertTrue(service.isEnabled(.mrApproval, workspace: workspace))
        XCTAssertTrue(service.isEnabled(.dependencyConflict, workspace: workspace))
        XCTAssertTrue(service.isEnabled(.sprintCompletion, workspace: workspace))
    }

    // MARK: - Deep Linking Tests

    @MainActor
    func testDeepLinkTargetForMergeRequest() {
        let notification = AppNotification(
            eventType: .newMergeRequest,
            title: "New MR",
            message: "Test",
            relatedItemId: UUID(),
            relatedItemType: "MergeRequest"
        )

        let target = service.deepLinkTarget(for: notification)
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.tab, .mergeRequests)
        XCTAssertEqual(target?.itemId, notification.relatedItemId)
    }

    @MainActor
    func testDeepLinkTargetForMRApproval() {
        let notification = AppNotification(
            eventType: .mrApproval,
            title: "MR Approved",
            message: "Test",
            relatedItemId: UUID(),
            relatedItemType: "MergeRequest"
        )

        let target = service.deepLinkTarget(for: notification)
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.tab, .mergeRequests)
    }

    @MainActor
    func testDeepLinkTargetForDependencyConflict() {
        let notification = AppNotification(
            eventType: .dependencyConflict,
            title: "Conflict",
            message: "Test",
            relatedItemId: UUID(),
            relatedItemType: "Ticket"
        )

        let target = service.deepLinkTarget(for: notification)
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.tab, .board)
        XCTAssertEqual(target?.itemType, "conflict")
    }

    @MainActor
    func testDeepLinkTargetForSprintCompletion() {
        let notification = AppNotification(
            eventType: .sprintCompletion,
            title: "Sprint Done",
            message: "Test",
            relatedItemId: UUID(),
            relatedItemType: "Sprint"
        )

        let target = service.deepLinkTarget(for: notification)
        XCTAssertNotNil(target)
        XCTAssertEqual(target?.tab, .sprints)
    }

    // MARK: - Notification Ordering Tests

    @MainActor
    func testGetNotificationsReturnsNewestFirst() async {
        for i in 0..<5 {
            let notification = AppNotification(
                eventType: .newMergeRequest,
                title: "MR #\(i)",
                message: "Message \(i)",
                createdAt: Date().addingTimeInterval(TimeInterval(i * 60))
            )
            notification.workspace = workspace
            modelContext.insert(notification)
        }
        try! modelContext.save()

        let notifications = service.getNotifications(workspace: workspace)
        XCTAssertEqual(notifications.count, 5)
        // Newest first
        XCTAssertEqual(notifications.first?.title, "MR #4")
        XCTAssertEqual(notifications.last?.title, "MR #0")
    }
}
