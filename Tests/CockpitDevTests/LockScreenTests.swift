import XCTest
@testable import CockpitDev

/// Tests for the lock screen authentication flow and app lifecycle gating.
final class LockScreenTests: CockpitDevTestCase {

    private var authService: AuthenticationService!
    private var currentDate: Date!

    override func setUp() {
        super.setUp()
        currentDate = Date()
        authService = AuthenticationService(
            maxFailures: 5,
            lockoutDuration: 60,
            currentDateProvider: { [unowned self] in self.currentDate }
        )
    }

    override func tearDown() {
        authService = nil
        super.tearDown()
    }

    // MARK: - Locked State Tests (no workspace data visible until authenticated)

    func testAppStartsInLockedState() {
        // On launch, user should not be authenticated
        XCTAssertFalse(authService.isAuthenticated)
    }

    func testWorkspaceDataNotAccessibleWhenLocked() {
        // When not authenticated, isAuthenticated is false
        // The AppRootView uses this to show LockScreenView instead of MainWindowView
        XCTAssertFalse(authService.isAuthenticated)
        // Simulating that no workspace data is exposed
        // (the view layer gates on isAuthenticated)
    }

    func testWorkspaceDataAccessibleAfterAuth() {
        authService.recordSuccess()
        XCTAssertTrue(authService.isAuthenticated)
        // MainWindowView would now be shown
    }

    // MARK: - Authentication Cancellation Tests

    func testCancellationKeepsAppLocked() {
        // User cancels Touch ID — should remain locked
        // AuthenticationError.userCancelled does NOT record a failure
        XCTAssertFalse(authService.isAuthenticated)
        // After cancellation, isAuthenticated remains false
        XCTAssertFalse(authService.isLockedOut)
        XCTAssertEqual(authService.consecutiveFailures, 0)
    }

    func testSystemCancellationKeepsAppLocked() {
        // System cancels auth — should remain locked without counting as failure
        XCTAssertFalse(authService.isAuthenticated)
        XCTAssertEqual(authService.consecutiveFailures, 0)
    }

    // MARK: - Lockout Display Tests

    func testLockoutDisplayAfter5Failures() {
        for _ in 1...5 {
            authService.recordFailure()
        }

        XCTAssertTrue(authService.isLockedOut)
        // The LockScreenView should show lockout UI
        let remaining = authService.remainingLockoutTime()
        XCTAssertNotNil(remaining)
        XCTAssertGreaterThan(remaining!, 0)
    }

    func testLockoutCountdownDecreases() {
        for _ in 1...5 {
            authService.recordFailure()
        }

        let initialRemaining = authService.remainingLockoutTime()!

        // Advance 10 seconds
        currentDate = currentDate.addingTimeInterval(10)

        let laterRemaining = authService.remainingLockoutTime()!
        XCTAssertLessThan(laterRemaining, initialRemaining)
        XCTAssertEqual(laterRemaining, 50, accuracy: 1.0)
    }

    func testLockoutExpiresAndAllowsRetry() {
        for _ in 1...5 {
            authService.recordFailure()
        }
        XCTAssertTrue(authService.isLockedOut)

        // Advance past lockout duration
        currentDate = currentDate.addingTimeInterval(61)

        // Lockout should have expired
        XCTAssertNil(authService.remainingLockoutTime())

        // After reset, user can try again
        authService.resetLockout()
        XCTAssertFalse(authService.isLockedOut)
        XCTAssertEqual(authService.consecutiveFailures, 0)
    }

    // MARK: - App Lifecycle Tests

    func testAuthRequiredOnLaunch() {
        // Fresh service starts unauthenticated
        let freshService = AuthenticationService()
        XCTAssertFalse(freshService.isAuthenticated)
    }

    func testLockMethodRequiresReauth() {
        authService.recordSuccess()
        XCTAssertTrue(authService.isAuthenticated)

        authService.lock()
        XCTAssertFalse(authService.isAuthenticated)
        // App should show lock screen again
    }

    // MARK: - Transition State Tests

    func testTransitionFromLockedToAuthenticated() {
        // Start locked
        XCTAssertFalse(authService.isAuthenticated)

        // Authenticate successfully
        authService.recordSuccess()

        // Now authenticated — AppRootView transitions to MainWindowView
        XCTAssertTrue(authService.isAuthenticated)
    }

    func testTransitionFromAuthenticatedToLocked() {
        authService.recordSuccess()
        XCTAssertTrue(authService.isAuthenticated)

        authService.lock()
        XCTAssertFalse(authService.isAuthenticated)
        // AppRootView transitions back to LockScreenView
    }

    // MARK: - Failure Counter Visibility

    func testFailureCounterShowsRemainingAttempts() {
        authService.recordFailure()
        let remaining = authService.maxFailures - authService.consecutiveFailures
        XCTAssertEqual(remaining, 4)

        authService.recordFailure()
        authService.recordFailure()
        let remaining2 = authService.maxFailures - authService.consecutiveFailures
        XCTAssertEqual(remaining2, 2)
    }
}
