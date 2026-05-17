import SwiftUI

/// Lock screen view that gates access to the app until the user authenticates.
/// Displays Touch ID prompt with password fallback, lockout timer, and error states.
struct LockScreenView: View {

    @Bindable var authService: AuthenticationService

    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var lockoutRemainingSeconds: Int = 0
    @State private var lockoutTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            lockIcon
                .padding(.bottom, 24)

            appTitle
                .padding(.bottom, 8)

            subtitle
                .padding(.bottom, 32)

            if authService.isLockedOut {
                lockoutView
            } else {
                unlockButton
            }

            if let error = errorMessage, !authService.isLockedOut {
                errorView(message: error)
                    .padding(.top, 16)
            }

            Spacer()

            failureIndicator
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            startLockoutTimerIfNeeded()
            triggerInitialAuth()
        }
        .onDisappear {
            stopLockoutTimer()
        }
    }

    // MARK: - Subviews

    private var lockIcon: some View {
        Image(systemName: authService.isLockedOut ? "lock.fill" : "lock.shield.fill")
            .font(.system(size: 48, weight: .light))
            .foregroundStyle(authService.isLockedOut ? .red.opacity(0.8) : .secondary)
            .symbolEffect(.pulse, isActive: isAuthenticating)
    }

    private var appTitle: some View {
        Text("Cockpit Dev")
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .foregroundStyle(.primary)
    }

    private var subtitle: some View {
        Text("Authenticate to unlock your workspaces")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.secondary)
    }

    private var unlockButton: some View {
        Button(action: { performAuthentication() }) {
            HStack(spacing: 8) {
                if isAuthenticating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "touchid")
                        .font(.system(size: 16, weight: .medium))
                }
                Text(isAuthenticating ? "Authenticating…" : "Unlock")
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(width: 180, height: 36)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 99/255, green: 102/255, blue: 241/255)) // accent indigo
        .controlSize(.large)
        .disabled(isAuthenticating)
        .keyboardShortcut(.defaultAction)
    }

    private var lockoutView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundStyle(.red)

            Text("Too many failed attempts")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)

            Text("Try again in \(lockoutRemainingSeconds) seconds")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            // Progress indicator for lockout
            ProgressView(value: lockoutProgress)
                .progressViewStyle(.linear)
                .frame(width: 180)
                .tint(.red.opacity(0.7))
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.red.opacity(0.05))
                .stroke(Color.red.opacity(0.15), lineWidth: 1)
        )
    }

    private func errorView(message: String) -> some View {
        Text(message)
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 240)
    }

    private var failureIndicator: some View {
        Group {
            if authService.consecutiveFailures > 0 && !authService.isLockedOut {
                let remaining = authService.maxFailures - authService.consecutiveFailures
                Text("\(remaining) attempt\(remaining == 1 ? "" : "s") remaining before lockout")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Computed Properties

    private var lockoutProgress: Double {
        guard authService.isLockedOut else { return 0 }
        let total = authService.lockoutDuration
        let remaining = Double(lockoutRemainingSeconds)
        return max(0, min(1, remaining / total))
    }

    // MARK: - Actions

    private func triggerInitialAuth() {
        guard !authService.isLockedOut else { return }
        performAuthentication()
    }

    private func performAuthentication() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        errorMessage = nil

        Task {
            do {
                try await authService.authenticate()
                // Success is handled by the parent view observing isAuthenticated
            } catch AuthenticationError.userCancelled {
                // User cancelled — remain locked, no error message
                errorMessage = nil
            } catch AuthenticationError.systemCancelled {
                // System cancelled — remain locked, no error message
                errorMessage = nil
            } catch AuthenticationError.lockedOut(let remaining) {
                errorMessage = nil
                lockoutRemainingSeconds = Int(remaining)
                startLockoutTimerIfNeeded()
            } catch AuthenticationError.authenticationFailed(let reason) {
                errorMessage = reason
                if authService.isLockedOut {
                    startLockoutTimerIfNeeded()
                }
            } catch AuthenticationError.biometryNotAvailable {
                errorMessage = "Biometric authentication is not available."
            } catch {
                errorMessage = error.localizedDescription
            }

            isAuthenticating = false
        }
    }

    // MARK: - Lockout Timer

    private func startLockoutTimerIfNeeded() {
        guard authService.isLockedOut else { return }
        stopLockoutTimer()

        if let remaining = authService.remainingLockoutTime() {
            lockoutRemainingSeconds = Int(ceil(remaining))
        } else {
            lockoutRemainingSeconds = 0
            authService.resetLockout()
            return
        }

        lockoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            Task { @MainActor in
                if let remaining = authService.remainingLockoutTime(), remaining > 0 {
                    lockoutRemainingSeconds = Int(ceil(remaining))
                } else {
                    lockoutRemainingSeconds = 0
                    authService.resetLockout()
                    stopLockoutTimer()
                }
            }
        }
    }

    private func stopLockoutTimer() {
        lockoutTimer?.invalidate()
        lockoutTimer = nil
    }
}

#Preview("Locked") {
    LockScreenView(authService: AuthenticationService())
        .frame(width: 500, height: 400)
}

#Preview("Locked Out") {
    let service = AuthenticationService()
    // Simulate lockout
    for _ in 0..<5 {
        service.recordFailure()
    }
    return LockScreenView(authService: service)
        .frame(width: 500, height: 400)
}
