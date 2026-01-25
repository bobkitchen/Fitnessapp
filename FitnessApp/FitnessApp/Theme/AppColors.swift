import SwiftUI

// MARK: - App Color Palette

/// Dark mode optimized color palette inspired by Athlytic and The Outsiders
extension Color {
    // MARK: - Backgrounds (Layered Depth)

    /// Near black primary background
    static let backgroundPrimary = Color(hex: "0D0D0F")

    /// Card surface background
    static let backgroundSecondary = Color(hex: "1A1A1E")

    /// Elevated cards background
    static let backgroundTertiary = Color(hex: "252529")

    // MARK: - Accent Colors

    /// Teal/mint - readiness indicator
    static let accentPrimary = Color(hex: "00D4AA")

    /// Purple - AI coach accent
    static let accentSecondary = Color(hex: "7B61FF")

    // MARK: - Status Colors

    /// Bright green for excellent status
    static let statusExcellent = Color(hex: "00E676")

    /// Teal for good status
    static let statusGood = Color(hex: "00D4AA")

    /// Amber for moderate status
    static let statusModerate = Color(hex: "FFB300")

    /// Red for low/warning status
    static let statusLow = Color(hex: "FF5252")

    // MARK: - Activity Colors

    /// Deep orange for running
    static let activityRun = Color(hex: "FF7043")

    /// Blue for cycling
    static let activityBike = Color(hex: "42A5F5")

    /// Cyan for swimming
    static let activitySwim = Color(hex: "26C6DA")

    /// Purple for strength training
    static let activityStrength = Color(hex: "AB47BC")

    // MARK: - PMC Chart Colors

    /// Fitness (CTL) line color
    static let chartFitness = Color(hex: "42A5F5")

    /// Fatigue (ATL) line color
    static let chartFatigue = Color(hex: "EC407A")

    /// Fresh form (positive TSB)
    static let chartFormFresh = Color(hex: "00E676")

    /// Tired form (negative TSB)
    static let chartFormTired = Color(hex: "FF7043")

    // MARK: - Text Colors

    /// Primary text - white
    static let textPrimary = Color.white

    /// Secondary text - 60% white
    static let textSecondary = Color(white: 0.6)

    /// Tertiary text - 40% white
    static let textTertiary = Color(white: 0.4)

    // MARK: - Border Colors

    /// Primary border - subtle white
    static let borderPrimary = Color(white: 0.2)

    // MARK: - Semantic Gradients

    /// Readiness ring gradient for high scores
    static var readinessGradientHigh: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "00E676"), Color(hex: "00D4AA")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Readiness ring gradient for medium scores
    static var readinessGradientMedium: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "FFB300"), Color(hex: "FF8F00")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Readiness ring gradient for low scores
    static var readinessGradientLow: LinearGradient {
        LinearGradient(
            colors: [Color(hex: "FF5252"), Color(hex: "D32F2F")],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Hex Color Initializer

extension Color {
    /// Initialize a Color from a hex string
    /// - Parameter hex: Hex color string (with or without #)
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Activity Category Color Extension

extension ActivityCategory {
    /// Returns the themed color for this activity category
    var themeColor: Color {
        switch self {
        case .run: return .activityRun
        case .bike: return .activityBike
        case .swim: return .activitySwim
        case .strength: return .activityStrength
        case .other: return .textTertiary
        }
    }
}

// MARK: - Training Readiness Color Extension

extension TrainingReadiness {
    /// Returns the themed color for this readiness level
    var themeColor: Color {
        switch self {
        case .fullyReady: return .statusExcellent
        case .mostlyReady: return .statusGood
        case .reducedCapacity: return .statusModerate
        case .restRecommended: return .statusLow
        }
    }

    /// Returns the gradient for the readiness ring
    var ringGradient: LinearGradient {
        switch self {
        case .fullyReady, .mostlyReady:
            return Color.readinessGradientHigh
        case .reducedCapacity:
            return Color.readinessGradientMedium
        case .restRecommended:
            return Color.readinessGradientLow
        }
    }
}

// MARK: - TSB (Form) Color Helper

extension Color {
    /// Returns the appropriate color for a TSB value
    static func forTSB(_ tsb: Double) -> Color {
        switch tsb {
        case 15...: return .statusExcellent
        case 5..<15: return .statusGood
        case -10..<5: return .chartFitness
        case -25..<(-10): return .statusModerate
        default: return .statusLow
        }
    }
}

// MARK: - Card Background Modifier

extension View {
    /// Applies the standard dark card background style
    func cardBackground(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
    }

    /// Applies an elevated dark card background style
    func elevatedCardBackground(cornerRadius: CGFloat = 20) -> some View {
        self
            .background(Color.backgroundTertiary)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

// MARK: - TSSType Quality Colors

extension TSSType {
    /// Color indicating data quality - green for best, orange for fallback
    var qualityColor: Color {
        switch qualityRank {
        case 3: return .statusExcellent  // Power
        case 2: return .statusGood       // Pace
        case 1: return .statusModerate   // HR
        default: return .statusLow       // Estimated
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            // Background layers demo
            VStack(spacing: 8) {
                Text("Backgrounds")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 12) {
                    VStack {
                        Rectangle()
                            .fill(Color.backgroundPrimary)
                            .frame(height: 50)
                        Text("Primary")
                            .font(.caption2)
                    }
                    VStack {
                        Rectangle()
                            .fill(Color.backgroundSecondary)
                            .frame(height: 50)
                        Text("Secondary")
                            .font(.caption2)
                    }
                    VStack {
                        Rectangle()
                            .fill(Color.backgroundTertiary)
                            .frame(height: 50)
                        Text("Tertiary")
                            .font(.caption2)
                    }
                }
            }

            // Status colors demo
            VStack(spacing: 8) {
                Text("Status Colors")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 12) {
                    Circle().fill(Color.statusExcellent).frame(width: 30, height: 30)
                    Circle().fill(Color.statusGood).frame(width: 30, height: 30)
                    Circle().fill(Color.statusModerate).frame(width: 30, height: 30)
                    Circle().fill(Color.statusLow).frame(width: 30, height: 30)
                }
            }

            // Activity colors demo
            VStack(spacing: 8) {
                Text("Activity Colors")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: 12) {
                    Circle().fill(Color.activityRun).frame(width: 30, height: 30)
                    Circle().fill(Color.activityBike).frame(width: 30, height: 30)
                    Circle().fill(Color.activitySwim).frame(width: 30, height: 30)
                    Circle().fill(Color.activityStrength).frame(width: 30, height: 30)
                }
            }

            // Card demo
            VStack(spacing: 8) {
                Text("Card Styles")
                    .font(.headline)
                    .foregroundStyle(Color.textPrimary)

                Text("Standard Card")
                    .foregroundStyle(Color.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .cardBackground()

                Text("Elevated Card")
                    .foregroundStyle(Color.textSecondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .elevatedCardBackground()
            }
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}
