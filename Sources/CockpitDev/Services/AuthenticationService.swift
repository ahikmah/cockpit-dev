import Foundation
import LocalAuthentication

// MARK: - Authentication Errors

/// Errors that can occur during authentication.
enum AuthenticationError: Error, LocalizedError {
    case authenticationFailed(String)
    case lockedOut(remainingSeconds: TimeInterval)
    case biometryNotAvailable
    case userCancelled
    case systemCancelled

    var errorDescription: String? {
        switch self {
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .lockedOut(let remaining):
            return "Account locked. Try again in \(Int(remaining)) seconds."
        case .biometryNotAvailable:
            return "Biometric authentication is not available on this device."
        case .userCancelled:
            return "Authentication was cancelled by the user."
        case .systemCancelled:
            return "Authentication was cancelled by the system."
        }
    }
}

// MARK: - AuthenticationService

/// Service responsible for app-level authentication using LocalAuthentication (Touch ID/password).
///
/// Implements a failure counter that locks the app after 5 consecutive failures for 60 seconds.
@Observable
class AuthenticationService {

    // MARK: - Properties

    /// Whether the user is currently authenticated.
    private(set) var isAuthenticated: Bool = false

    /// Whether the account is currently locked out due to too many failures.
    private(set) var isLockedOut: Bool = false

    /// The number of consecutive failed authentication attempts.
    private(set) var consecutiveFailures: Int = 0

    /// The timestamp when the lockout started (nil if not locked out).
    private(set) var lockoutStartTime: Date?

    /// Maximum consecutive failures before lockout.
    let maxFailures: Int

    /// Duration of lockout in seconds.
    let lockoutDuration: TimeInterval

    /// Provides the current date (injectable for testing).
    var currentDateProvider: () -> Date

    // MARK: - Initialization

    /// Creates an AuthenticationService with configurable lockout parameters.
    /// - Parameters:
    ///   - maxFailures: Maximum consecutive failures before lockout (default: 5).
    ///   - lockoutDuration: Lockout duration in seconds (default: 60).
    ///   - currentDateProvider: Closure providing the current date (default: Date()).
    init(
        maxFailures: Int = AppConstants.maxAuthFailures,
        lockoutDuration: TimeInterval = AppConstants.authLockoutDuration,
        currentDateProvider: @escaping () -> Date = { Date() }
    ) {
        self.maxFailures = maxFailures
        self.lockoutDuration = lockoutDuration
        self.currentDateProvider = currentDateProvider
    }

    // MARK: - Authentication

    /// Attempts to authenticate the user using Touch ID or device password.
    /// - Returns: `true` if authentication succeeded, `false` otherwise.
    /// - Throws: `AuthenticationError.lockedOut` if the account is locked.
    @MainActor
    @discardableResult
    func authenticate() async throws -> Bool {
        // Check lockout status
        if let remainingTime = remainingLockoutTime(), remainingTime > 0 {
            throw AuthenticationError.lockedOut(remainingSeconds: remainingTime)
        } else if lockoutStartTime != nil {
            // Lockout has expired, reset
            resetLockout()
        }

        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(
            .deviceOwnerAuthentication,
            error: &error
        )

        guard canEvaluate else {
            recordFailure()
            throw AuthenticationError.biometryNotAvailable
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Authenticate to access Cockpit Dev"
            )

            if success {
                recordSuccess()
                return true
            } else {
                recordFailure()
                return false
            }
        } catch let laError as LAError {
            switch laError.code {
            case .userCancel:
                // User cancellation does not count as a failure
                throw AuthenticationError.userCancelled
            case .systemCancel:
                throw AuthenticationError.systemCancelled
            case .authenticationFailed:
                recordFailure()
                if isLockedOut {
                    throw AuthenticationError.lockedOut(
                        remainingSeconds: remainingLockoutTime() ?? lockoutDuration
                    )
                }
                throw AuthenticationError.authenticationFailed("Authentication failed")
            default:
                recordFailure()
                throw AuthenticationError.authenticationFailed(laError.localizedDescription)
            }
        }
    }

    // MARK: - Failure Counter

    /// Records a successful authentication, resetting the failure counter.
    func recordSuccess() {
        isAuthenticated = true
        consecutiveFailures = 0
        lockoutStartTime = nil
        isLockedOut = false
    }

    /// Records a failed authentication attempt and triggers lockout if threshold is reached.
    func recordFailure() {
        consecutiveFailures += 1

        if consecutiveFailures >= maxFailures {
            lockoutStartTime = currentDateProvider()
            isLockedOut = true
        }
    }

    /// Returns the remaining lockout time in seconds, or nil if not locked out.
    func remainingLockoutTime() -> TimeInterval? {
        guard let startTime = lockoutStartTime else { return nil }
        let elapsed = currentDateProvider().timeIntervalSince(startTime)
        let remaining = lockoutDuration - elapsed
        return remaining > 0 ? remaining : nil
    }

    /// Resets the lockout state and failure counter.
    func resetLockout() {
        lockoutStartTime = nil
        isLockedOut = false
        consecutiveFailures = 0
    }

    /// Locks the app (sets authenticated to false).
    func lock() {
        isAuthenticated = false
    }
}
