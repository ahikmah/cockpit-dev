import XCTest
@testable import CockpitDev

final class AuthenticationServiceTests: CockpitDevTestCase {

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

    // MARK: - Initial State Tests

    func testInitialStateNotAuthenticated() {
        XCTAssertFalse(authService.isAuthenticated)
    }

    func testInitialStateNotLockedOut() {
        XCTAssertFalse(authService.isLockedOut)
    }

    func testInitialStateZeroFailures() {
        XCTAssertEqual(authService.consecutiveFailures, 0)
    }

    // MARK: - Failure Counter Tests

    func testRecordFailureIncrementsCounter() {
        authService.recordFailure()
        XCTAssertEqual(authService.consecutiveFailures, 1)

        authService.recordFailure()
        XCTAssertEqual(authService.consecutiveFailures, 2)
    }

    func testRecordSuccessResetsCounter() {
        authService.recordFailure()
        authService.recordFailure()
        authService.recordFailure()
        XCTAssertEqual(authService.consecutiveFailures, 3)

        authService.recordSuccess()
        XCTAssertEqual(authService.consecutiveFailures, 0)
        XCTAssertTrue(authService.isAuthenticated)
    }

    func testLockoutAfter5ConsecutiveFailures() {
        for _ in 1...4 {
            authService.recordFailure()
            XCTAssertFalse(authService.isLockedOut)
        }

        // 5th failure triggers lockout
        authService.recordFailure()
        XCTAssertTrue(authService.isLockedOut)
        XCTAssertEqual(authService.consecutiveFailures, 5)
        XCTAssertNotNil(authService.lockoutStartTime)
    }

    func testLockoutNotTriggeredBefore5Failures() {
        for _ in 1...4 {
            authService.recordFailure()
        }
        XCTAssertFalse(authService.isLockedOut)
        XCTAssertNil(authService.lockoutStartTime)
    }

    // MARK: - Lockout Duration Tests

    func testRemainingLockoutTimeWhenLocked() {
        // Trigger lockout
        for _ in 1...5 {
            authService.recordFailure()
        }

        // Immediately after lockout, remaining time should be close to 60 seconds
        let remaining = authService.remainingLockoutTime()
        XCTAssertNotNil(remaining)
        XCTAssertEqual(remaining!, 60, accuracy: 1.0)
    }

    func testRemainingLockoutTimeDecreasesOverTime() {
        // Trigger lockout
        for _ in 1...5 {
            authService.recordFailure()
        }

        // Advance time by 30 seconds
        currentDate = currentDate.addingTimeInterval(30)

        let remaining = authService.remainingLockoutTime()
        XCTAssertNotNil(remaining)
        XCTAssertEqual(remaining!, 30, accuracy: 1.0)
    }

    func testLockoutExpiresAfter60Seconds() {
        // Trigger lockout
        for _ in 1...5 {
            authService.recordFailure()
        }

        // Advance time by 61 seconds (past lockout duration)
        currentDate = currentDate.addingTimeInterval(61)

        let remaining = authService.remainingLockoutTime()
        XCTAssertNil(remaining)
    }

    func testRemainingLockoutTimeNilWhenNotLocked() {
        let remaining = authService.remainingLockoutTime()
        XCTAssertNil(remaining)
    }

    // MARK: - Reset Tests

    func testResetLockoutClearsState() {
        // Trigger lockout
        for _ in 1...5 {
            authService.recordFailure()
        }
        XCTAssertTrue(authService.isLockedOut)

        authService.resetLockout()
        XCTAssertFalse(authService.isLockedOut)
        XCTAssertEqual(authService.consecutiveFailures, 0)
        XCTAssertNil(authService.lockoutStartTime)
    }

    // MARK: - Lock Tests

    func testLockSetsAuthenticatedToFalse() {
        authService.recordSuccess()
        XCTAssertTrue(authService.isAuthenticated)

        authService.lock()
        XCTAssertFalse(authService.isAuthenticated)
    }

    // MARK: - Edge Cases

    func testMultipleSuccessesAfterFailures() {
        authService.recordFailure()
        authService.recordFailure()
        authService.recordSuccess()
        XCTAssertEqual(authService.consecutiveFailures, 0)

        authService.recordFailure()
        XCTAssertEqual(authService.consecutiveFailures, 1)
    }

    func testFailuresAfterLockoutExpiry() {
        // Trigger lockout
        for _ in 1...5 {
            authService.recordFailure()
        }
        XCTAssertTrue(authService.isLockedOut)

        // Advance time past lockout
        currentDate = currentDate.addingTimeInterval(61)

        // Reset lockout (simulating what authenticate() does)
        authService.resetLockout()

        // New failures should start counting from 0
        authService.recordFailure()
        XCTAssertEqual(authService.consecutiveFailures, 1)
        XCTAssertFalse(authService.isLockedOut)
    }

    func testExactly5FailuresTriggersLockout() {
        for i in 1...5 {
            authService.recordFailure()
            if i < 5 {
                XCTAssertFalse(authService.isLockedOut, "Should not be locked at \(i) failures")
            }
        }
        XCTAssertTrue(authService.isLockedOut, "Should be locked at 5 failures")
    }

    func testMoreThan5FailuresStaysLocked() {
        for _ in 1...7 {
            authService.recordFailure()
        }
        XCTAssertTrue(authService.isLockedOut)
        XCTAssertEqual(authService.consecutiveFailures, 7)
    }

    func testCustomMaxFailures() {
        let customService = AuthenticationService(
            maxFailures: 3,
            lockoutDuration: 30,
            currentDateProvider: { [unowned self] in self.currentDate }
        )

        for _ in 1...2 {
            customService.recordFailure()
        }
        XCTAssertFalse(customService.isLockedOut)

        customService.recordFailure()
        XCTAssertTrue(customService.isLockedOut)
    }

    func testCustomLockoutDuration() {
        let customService = AuthenticationService(
            maxFailures: 5,
            lockoutDuration: 30,
            currentDateProvider: { [unowned self] in self.currentDate }
        )

        for _ in 1...5 {
            customService.recordFailure()
        }

        // After 25 seconds, still locked
        currentDate = currentDate.addingTimeInterval(25)
        XCTAssertNotNil(customService.remainingLockoutTime())

        // After 31 seconds, unlocked
        currentDate = currentDate.addingTimeInterval(6)
        XCTAssertNil(customService.remainingLockoutTime())
    }
}
