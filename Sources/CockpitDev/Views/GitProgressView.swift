import SwiftUI

// MARK: - Git Progress View

/// A view that displays progress for ongoing Git operations (clone, pull, push).
///
/// Shows a progress bar with phase information and percentage.
/// Implements Requirement 15.7: Progress indicator during Git operations.
struct GitProgressView: View {
    let title: String
    let message: String
    let percentage: Int?
    let isIndeterminate: Bool

    init(title: String, message: String, percentage: Int? = nil) {
        self.title = title
        self.message = message
        self.percentage = percentage
        self.isIndeterminate = percentage == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16, weight: .medium))

                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))

                Spacer()

                if let percentage = percentage {
                    Text("\(percentage)%")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if isIndeterminate {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
            } else if let percentage = percentage {
                ProgressView(value: Double(percentage), total: 100)
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
            }

            Text(message)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.background)
                .shadow(color: .black.opacity(0.04), radius: 3, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

// MARK: - Git Operation Progress Sheet

/// A sheet view that displays progress for a Git operation with a cancel option.
struct GitOperationProgressSheet: View {
    let operationName: String
    @Binding var message: String
    @Binding var percentage: Int?
    @Binding var isComplete: Bool
    var onCancel: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(spacing: 24) {
            // Header
            HStack {
                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(isComplete ? .green : .accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(operationName)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))

                    Text(isComplete ? "Operation complete" : "In progress...")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Progress
            VStack(alignment: .leading, spacing: 8) {
                if isComplete {
                    ProgressView(value: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.green)
                } else if let percentage = percentage {
                    ProgressView(value: Double(percentage), total: 100)
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                } else {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.accentColor)
                }

                Text(message)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Actions
            HStack {
                Spacer()

                if isComplete {
                    Button("Done") {
                        onDismiss?()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                } else if let onCancel = onCancel {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
        .padding(24)
        .frame(width: 400)
    }

    private var iconName: String {
        if isComplete {
            return "checkmark.circle.fill"
        }
        switch operationName.lowercased() {
        case let name where name.contains("clone"):
            return "arrow.down.circle"
        case let name where name.contains("pull"):
            return "arrow.down.circle"
        case let name where name.contains("push"):
            return "arrow.up.circle"
        default:
            return "arrow.triangle.2.circlepath"
        }
    }
}

// MARK: - Git Error View

/// A view that displays Git operation errors with the full error output.
struct GitErrorView: View {
    let title: String
    let error: GitOperationError
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.red)

                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))

                Spacer()
            }

            // Error description
            if let description = error.errorDescription {
                ScrollView {
                    Text(description)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
            }

            // Actions
            HStack {
                Spacer()

                if let onRetry = onRetry {
                    Button("Retry") {
                        onRetry()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Button("Dismiss") {
                    onDismiss?()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Git Progress") {
    VStack(spacing: 16) {
        GitProgressView(
            title: "Cloning Repository",
            message: "Receiving objects: 45% (123/456)",
            percentage: 45
        )

        GitProgressView(
            title: "Pushing Changes",
            message: "Counting objects...",
            percentage: nil
        )
    }
    .padding()
    .frame(width: 400)
}
#endif
