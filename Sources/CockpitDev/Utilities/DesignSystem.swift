import SwiftUI

/// Design system tokens for Cockpit Dev.
/// Provides consistent colors, typography, spacing, and component styles
/// following a crisp dev-lead console aesthetic with restrained pastel status colors.
enum DesignSystem {

    // MARK: - Colors (Adaptive: Light + Dark Mode)

    enum Colors {
        static let background = adaptive(light: 0xF4F5F7, dark: 0x171A21)
        static let surface = adaptive(light: 0xFBFCFD, dark: 0x20242D)
        static let surfaceElevated = adaptive(light: 0xFFFFFF, dark: 0x252B36)
        static let navigation = adaptive(light: 0xFFFFFF, dark: 0x1B1F27)
        static let navigationActive = adaptive(light: 0x202733, dark: 0x303846)
        static let navigationActiveText = adaptive(light: 0xFFFFFF, dark: 0xF4F7FB)
        static let sidebar = adaptive(light: 0xF3F5F8, dark: 0x1C212A)
        static let sidebarSelected = adaptive(light: 0xE6EEFC, dark: 0x293142)
        static let sidebarIcon = adaptive(light: 0xF7F9FC, dark: 0x252B36)
        static let border = adaptive(light: 0xD8DDE6, dark: 0x343A46)
        static let borderFocused = Color(nsColor: .keyboardFocusIndicatorColor)
        static let textPrimary = Color(nsColor: .labelColor)
        static let textSecondary = Color(nsColor: .secondaryLabelColor)
        static let textTertiary = Color(nsColor: .tertiaryLabelColor)
        static let accent = adaptive(light: 0x4267B2, dark: 0x8AA8FF)
        static let accentSoft = adaptive(light: 0xDFE9FF, dark: 0x2B344A)
        static let success = adaptive(light: 0x246453, dark: 0xA7EAD3)
        static let successSoft = adaptive(light: 0xDFF3EA, dark: 0x1F3A35)
        static let warning = adaptive(light: 0x8B5E16, dark: 0xFFD28A)
        static let warningSoft = adaptive(light: 0xF7E8C8, dark: 0x3B3120)
        static let danger = adaptive(light: 0x9D3D38, dark: 0xFFAAA2)
        static let dangerSoft = adaptive(light: 0xF7DDDD, dark: 0x3D2929)
        static let mutedBlue = adaptive(light: 0xE1EBFF, dark: 0x26334F)
        static let timelineBarText = adaptive(light: 0x17202A, dark: 0xE8EEF6)
        static let timelineBacklog = adaptive(light: 0xE7EAF0, dark: 0x30343D)
        static let timelineBacklogBorder = adaptive(light: 0xAAB3C2, dark: 0x687184)
        static let timelineTodo = adaptive(light: 0xD9E6F8, dark: 0x273347)
        static let timelineTodoBorder = adaptive(light: 0x7A98C7, dark: 0x6383B6)
        static let timelineInProgress = adaptive(light: 0xDDF0EA, dark: 0x263C3A)
        static let timelineInProgressBorder = adaptive(light: 0x6AAE9E, dark: 0x69B7A7)
        static let timelineInReview = adaptive(light: 0xE9DDF5, dark: 0x3A314A)
        static let timelineInReviewBorder = adaptive(light: 0xA47AC9, dark: 0xA78BD0)
        static let timelineDone = adaptive(light: 0xDFF1DC, dark: 0x25402F)
        static let timelineDoneBorder = adaptive(light: 0x74AD72, dark: 0x7CC78B)
        static let timelineConflict = adaptive(light: 0xF2DEDA, dark: 0x3D2C2C)
        static let timelineConflictBorder = adaptive(light: 0xC77770, dark: 0xE08C85)
        static let timelineUnassigned = adaptive(light: 0xE4E9F5, dark: 0x2D3445)
        static let timelineUnassignedBorder = adaptive(light: 0x8EA1C4, dark: 0x778BB8)

        private static func adaptive(light: UInt32, dark: UInt32) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            })
        }
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
        static let spacing10: CGFloat = 10
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
        static let width: CGFloat = 236
        static let minWidth: CGFloat = 220
        static let maxWidth: CGFloat = 300
        static let chromeHeight: CGFloat = 52
    }

    // MARK: - Animation

    enum Motion {
        static let fast = Animation.easeOut(duration: 0.15)
        static let normal = Animation.easeInOut(duration: 0.25)
        static let spring = Animation.spring(response: 0.35, dampingFraction: 0.85)
    }
}

private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
