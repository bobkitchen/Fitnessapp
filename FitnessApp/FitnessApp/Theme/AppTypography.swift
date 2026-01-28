import SwiftUI

// MARK: - App Typography System

/// Typography definitions using SF Pro and SF Pro Rounded
/// All fonts support Dynamic Type scaling for accessibility
enum AppFont {
    // MARK: - Display Fonts (SF Pro Rounded for warmth)

    /// Large display text - 56pt bold rounded, scales with Dynamic Type
    static var displayLarge: Font {
        Font.system(size: 56, weight: .bold, design: .rounded)
    }

    /// Medium display text - 44pt bold rounded, scales with Dynamic Type
    static var displayMedium: Font {
        Font.system(size: 44, weight: .bold, design: .rounded)
    }

    /// Small display text - 34pt bold rounded, scales with Dynamic Type
    static var displaySmall: Font {
        Font.system(size: 34, weight: .bold, design: .rounded)
    }

    // MARK: - Title Fonts

    /// Large title - 22pt semibold, scales with Dynamic Type
    static var titleLarge: Font {
        Font.system(size: 22, weight: .semibold)
    }

    /// Medium title - 18pt semibold, scales with Dynamic Type
    static var titleMedium: Font {
        Font.system(size: 18, weight: .semibold)
    }

    // MARK: - Metric Fonts (Tabular for alignment)

    /// Super hero metric - 64pt bold rounded (for readiness score)
    static var metricSuperHero: Font {
        Font.system(size: 64, weight: .bold, design: .rounded)
            .monospacedDigit()
    }

    /// Hero metric - 48pt bold rounded with monospaced digits
    static var metricHero: Font {
        Font.system(size: 48, weight: .bold, design: .rounded)
            .monospacedDigit()
    }

    /// Large metric - 32pt semibold rounded with monospaced digits
    static var metricLarge: Font {
        Font.system(size: 32, weight: .semibold, design: .rounded)
            .monospacedDigit()
    }

    /// Medium metric - 28pt semibold rounded (increased from 24pt)
    static var metricMedium: Font {
        Font.system(size: 28, weight: .semibold, design: .rounded)
            .monospacedDigit()
    }

    /// Small metric - 18pt semibold rounded with monospaced digits
    static var metricSmall: Font {
        Font.system(size: 18, weight: .semibold, design: .rounded)
            .monospacedDigit()
    }

    // MARK: - Body Fonts (SF Pro for readability)

    /// Large body text - 17pt regular, scales with Dynamic Type
    static var bodyLarge: Font {
        .body
    }

    /// Medium body text - 15pt regular, scales with Dynamic Type
    static var bodyMedium: Font {
        .subheadline
    }

    /// Small body text - 13pt regular, scales with Dynamic Type
    static var bodySmall: Font {
        .footnote
    }

    // MARK: - Label Fonts

    /// Large label - 13pt semibold, scales with Dynamic Type
    static var labelLarge: Font {
        Font.system(.footnote, design: .default, weight: .semibold)
    }

    /// Medium label - 12pt medium, scales with Dynamic Type
    static var labelMedium: Font {
        Font.system(.caption, design: .default, weight: .medium)
    }

    /// Small label - 11pt medium with small caps, scales with Dynamic Type
    static var labelSmall: Font {
        Font.system(.caption2, design: .default, weight: .medium)
            .uppercaseSmallCaps()
    }

    // MARK: - Caption Fonts

    /// Large caption - 12pt regular, scales with Dynamic Type
    static var captionLarge: Font {
        .caption
    }

    /// Small caption - 10pt regular, scales with Dynamic Type
    static var captionSmall: Font {
        .caption2
    }
}

// MARK: - Text Style Modifiers

extension View {
    /// Applies hero metric styling with optional color
    func heroMetricStyle(color: Color = .textPrimary) -> some View {
        self
            .font(AppFont.metricHero)
            .foregroundStyle(color)
    }

    /// Applies large metric styling with optional color
    func largeMetricStyle(color: Color = .textPrimary) -> some View {
        self
            .font(AppFont.metricLarge)
            .foregroundStyle(color)
    }

    /// Applies medium metric styling with optional color
    func mediumMetricStyle(color: Color = .textPrimary) -> some View {
        self
            .font(AppFont.metricMedium)
            .foregroundStyle(color)
    }

    /// Applies small metric styling with optional color
    func smallMetricStyle(color: Color = .textPrimary) -> some View {
        self
            .font(AppFont.metricSmall)
            .foregroundStyle(color)
    }

    /// Applies section header styling
    func sectionHeaderStyle() -> some View {
        self
            .font(AppFont.labelSmall)
            .foregroundStyle(Color.textTertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    /// Applies card title styling
    func cardTitleStyle() -> some View {
        self
            .font(AppFont.labelLarge)
            .foregroundStyle(Color.textSecondary)
    }

    /// Applies card subtitle styling
    func cardSubtitleStyle() -> some View {
        self
            .font(AppFont.captionLarge)
            .foregroundStyle(Color.textTertiary)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {
            // Display fonts
            VStack(alignment: .leading, spacing: 8) {
                Text("Display Fonts")
                    .sectionHeaderStyle()

                Text("Display Large")
                    .font(AppFont.displayLarge)
                    .foregroundStyle(Color.textPrimary)

                Text("Display Medium")
                    .font(AppFont.displayMedium)
                    .foregroundStyle(Color.textPrimary)

                Text("Display Small")
                    .font(AppFont.displaySmall)
                    .foregroundStyle(Color.textPrimary)
            }

            Divider().background(Color.textTertiary)

            // Metric fonts
            VStack(alignment: .leading, spacing: 8) {
                Text("Metric Fonts")
                    .sectionHeaderStyle()

                Text("78")
                    .heroMetricStyle(color: .statusExcellent)

                Text("123")
                    .largeMetricStyle(color: .chartFitness)

                Text("456")
                    .mediumMetricStyle(color: .statusModerate)

                Text("789")
                    .smallMetricStyle()
            }

            Divider().background(Color.textTertiary)

            // Body fonts
            VStack(alignment: .leading, spacing: 8) {
                Text("Body Fonts")
                    .sectionHeaderStyle()

                Text("Body Large - The quick brown fox")
                    .font(AppFont.bodyLarge)
                    .foregroundStyle(Color.textPrimary)

                Text("Body Medium - jumps over the lazy dog")
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(Color.textSecondary)

                Text("Body Small - while the cat watches")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Color.textTertiary)
            }

            Divider().background(Color.textTertiary)

            // Labels
            VStack(alignment: .leading, spacing: 8) {
                Text("Labels")
                    .sectionHeaderStyle()

                Text("Label Large")
                    .font(AppFont.labelLarge)
                    .foregroundStyle(Color.textPrimary)

                Text("Label Medium")
                    .font(AppFont.labelMedium)
                    .foregroundStyle(Color.textSecondary)

                Text("Label Small")
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}
