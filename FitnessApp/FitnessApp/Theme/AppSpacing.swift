import SwiftUI

// MARK: - Spacing System (4pt Grid)

/// Consistent spacing values based on a 4-point grid system
enum Spacing {
    /// 2pt - Extra extra extra small
    static let xxxs: CGFloat = 2

    /// 4pt - Extra extra small
    static let xxs: CGFloat = 4

    /// 8pt - Extra small
    static let xs: CGFloat = 8

    /// 12pt - Small
    static let sm: CGFloat = 12

    /// 16pt - Medium (default)
    static let md: CGFloat = 16

    /// 20pt - Medium large
    static let ml: CGFloat = 20

    /// 24pt - Large
    static let lg: CGFloat = 24

    /// 32pt - Extra large
    static let xl: CGFloat = 32

    /// 40pt - Extra extra large
    static let xxl: CGFloat = 40

    /// 48pt - Extra extra extra large
    static let xxxl: CGFloat = 48
}

// MARK: - Corner Radius Constants

/// Consistent corner radius values
enum CornerRadius {
    /// 8pt - Small elements (buttons, badges)
    static let small: CGFloat = 8

    /// 12pt - Medium elements (small cards)
    static let medium: CGFloat = 12

    /// 16pt - Large elements (standard cards)
    static let large: CGFloat = 16

    /// 20pt - Extra large elements (hero cards)
    static let extraLarge: CGFloat = 20

    /// 24pt - Full rounded for circular elements
    static let full: CGFloat = 24
}

// MARK: - Icon Sizes

/// Standard icon sizing
enum IconSize {
    /// 12pt - Tiny icons
    static let tiny: CGFloat = 12

    /// 16pt - Small icons
    static let small: CGFloat = 16

    /// 20pt - Medium icons
    static let medium: CGFloat = 20

    /// 24pt - Large icons
    static let large: CGFloat = 24

    /// 32pt - Extra large icons
    static let extraLarge: CGFloat = 32

    /// 44pt - Touch target minimum
    static let touchTarget: CGFloat = 44
}

// MARK: - Layout Constants

/// Common layout measurements
enum Layout {
    /// Minimum touch target size (44pt per Apple HIG)
    static let minTouchTarget: CGFloat = 44

    /// Standard card height
    static let cardHeight: CGFloat = 100

    /// Compact card height
    static let cardHeightCompact: CGFloat = 80

    /// Hero ring size
    static let heroRingSize: CGFloat = 200

    /// Chart height - compact
    static let chartHeightCompact: CGFloat = 80

    /// Chart height - standard
    static let chartHeightStandard: CGFloat = 150

    /// Chart height - expanded
    static let chartHeightExpanded: CGFloat = 250

    /// Screen edge padding
    static let screenPadding: CGFloat = Spacing.md

    /// Section spacing
    static let sectionSpacing: CGFloat = Spacing.lg

    /// Card spacing
    static let cardSpacing: CGFloat = Spacing.sm
}

// MARK: - Spacing Modifier Extensions

extension View {
    /// Applies standard screen edge padding
    func screenPadding() -> some View {
        self.padding(Layout.screenPadding)
    }

    /// Applies standard card internal padding
    func cardPadding() -> some View {
        self.padding(Spacing.md)
    }

    /// Applies compact card internal padding
    func compactCardPadding() -> some View {
        self.padding(Spacing.sm)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Spacing Scale")
                .sectionHeaderStyle()

            VStack(alignment: .leading, spacing: Spacing.xs) {
                SpacingDemo(name: "xxxs", value: Spacing.xxxs)
                SpacingDemo(name: "xxs", value: Spacing.xxs)
                SpacingDemo(name: "xs", value: Spacing.xs)
                SpacingDemo(name: "sm", value: Spacing.sm)
                SpacingDemo(name: "md", value: Spacing.md)
                SpacingDemo(name: "ml", value: Spacing.ml)
                SpacingDemo(name: "lg", value: Spacing.lg)
                SpacingDemo(name: "xl", value: Spacing.xl)
                SpacingDemo(name: "xxl", value: Spacing.xxl)
                SpacingDemo(name: "xxxl", value: Spacing.xxxl)
            }

            Text("Corner Radii")
                .sectionHeaderStyle()
                .padding(.top, Spacing.md)

            HStack(spacing: Spacing.md) {
                RadiusDemo(name: "sm", value: CornerRadius.small)
                RadiusDemo(name: "md", value: CornerRadius.medium)
                RadiusDemo(name: "lg", value: CornerRadius.large)
                RadiusDemo(name: "xl", value: CornerRadius.extraLarge)
            }
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}

// MARK: - Preview Helpers

private struct SpacingDemo: View {
    let name: String
    let value: CGFloat

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Rectangle()
                .fill(Color.accentPrimary)
                .frame(width: value, height: 20)

            Text("\(name): \(Int(value))pt")
                .font(AppFont.bodySmall)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

private struct RadiusDemo: View {
    let name: String
    let value: CGFloat

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            RoundedRectangle(cornerRadius: value)
                .fill(Color.backgroundSecondary)
                .frame(width: 50, height: 50)

            Text(name)
                .font(AppFont.captionSmall)
                .foregroundStyle(Color.textTertiary)
        }
    }
}
