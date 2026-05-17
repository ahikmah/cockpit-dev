import SwiftUI

/// Design system tokens for Cockpit Dev.
/// Provides consistent colors, typography, spacing, and component styles
/// following a modern, soft aesthetic inspired by Linear, Notion, and Arc Browser.
enum DesignSystem {

    // MARK: - Colors (Adaptive: Light + Dark Mode)

    enum Colors {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let surface = Color(nsColor: .controlBackgroundColor)
        static let surfaceElevated = Color(nsColor: .underPageBackgroundColor)
        static let border = Color(nsColor: .separatorColor)
        static let borderFocused = Color(nsColor: .keyboardFocusIndicatorColor)
        static let textPrimary = Color(nsColor: .labelColor)
        static let textSecondary = Color(nsColor: .secondaryLabelColor)
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)
        static let accent = Color(red: 0.388, green: 0.4, blue: 0.945)
        static let accentSoft = Color(red: 0.388, green: 0.4, blue: 0.945).opacity(0.12)
        static let success = Color(red: 0.063, green: 0.725, blue: 0.506)
        static let warning = Color(red: 0.961, green: 0.62, blue: 0.043)
        static let danger = Color(red: 0.937, green: 0.267, blue: 0.267)
        static let dangerSoft = Color(red: 0.937, green: 0.267, blue: 0.267).opacity(0.1)
    }

    // MARK: - Typography

    enum Typography {
        static let headingLarge = Font.system(size: 24, weight: .semibold, design: .rounded)
        static let headingMedium = Font.system(size: 18, weight: .semibold, design: .rounded)
        static let headingSmall = Font.system(size: 14, weight: .semibold, design: .rounded)
        static let bodyRegular = Font.system(size: 13, weight: .regular)
        static let bodyMedium = Font.system(size: 13, weight: .medium)
        static let caption = Font.system(size: 11, weight: .regular)
        static let captionMedium = Font.system(size: 11, weight: .medium)
        static let monospace = Font.system(size: 12, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing

    enum Spacing {
        static let spacing2: CGFloat = 2
        static let spacing4: CGFloat = 4
        static let spacing6: CGFloat = 6
        static let spacing8: CGFloat = 8
        static let spacing12: CGFloat = 12
        static let spacing16: CGFloat = 16
        static let spacing20: CGFloat = 20
        static let spacing24: CGFloat = 24
        static let spacing32: CGFloat = 32
        static let spacing48: CGFloat = 48
    }

    // MARK: - Corner Radius

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
        static let xl: CGFloat = 20
    }

    // MARK: - Sidebar

    enum Sidebar {
        static let width: CGFloat = 240
        static let minWidth: CGFloat = 200
        static let maxWidth: CGFloat = 320
    }

    // MARK: - Animation

    enum Motion {
        static let fast = Animation.easeOut(duration: 0.15)
        static let normal = Animation.easeInOut(duration: 0.25)
        static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    }
}
