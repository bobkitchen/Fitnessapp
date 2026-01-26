import SwiftUI

// MARK: - App Color Palette

/// "Refined Dark Athletic" color palette
/// Inspired by Whoop 4.0, Oura Ring, Garmin MARQ, luxury sports watches
extension Color {
    // MARK: - Backgrounds (Warmer Blacks with Layered Depth)

    /// Deeper, slightly warm black primary background
    static let backgroundPrimary = Color(hex: "0A0A0C")

    /// Card surface background
    static let backgroundSecondary = Color(hex: "141418")

    /// Elevated elements background
    static let backgroundTertiary = Color(hex: "1E1E24")

    // MARK: - Signature Accent (Warm Amber/Gold - Premium Feel)

    /// Amber gold - THE brand color for positive/ready states
    static let accentPrimary = Color(hex: "F5A623")

    /// Light gold for highlights
    static let accentSecondary = Color(hex: "FFD54F")

    // MARK: - Status Colors (Simplified to 3 Clear States)

    /// Soft green for optimal/excellent status (not neon)
    static let statusOptimal = Color(hex: "4ADE80")

    /// Amber for moderate status (matches accent)
    static let statusModerate = Color(hex: "F5A623")

    /// Soft coral red for low/warning status
    static let statusLow = Color(hex: "F87171")

    // Legacy aliases for backwards compatibility
    static var statusExcellent: Color { statusOptimal }
    static var statusGood: Color { statusOptimal }

    // MARK: - Data/Metric Colors (Cool Blues for Visualization)

    /// Soft blue for Fitness (CTL)
    static let metricPrimary = Color(hex: "60A5FA")

    /// Soft purple for Fatigue (ATL)
    static let metricSecondary = Color(hex: "818CF8")

    /// Soft teal for Form (TSB)
    static let metricTertiary = Color(hex: "34D399")

    // MARK: - Activity Colors (Subtle, Not Saturated)

    /// Soft orange for running
    static let activityRun = Color(hex: "FB923C")

    /// Soft blue for cycling
    static let activityBike = Color(hex: "60A5FA")

    /// Soft cyan for swimming
    static let activitySwim = Color(hex: "22D3EE")

    /// Soft purple for strength training
    static let activityStrength = Color(hex: "A78BFA")

    // MARK: - PMC Chart Colors

    /// Fitness (CTL) line color - soft blue
    static let chartFitness = Color(hex: "60A5FA")

    /// Fatigue (ATL) line color - warm coral (contrast with blue fitness line)
    static let chartFatigue = Color(hex: "FB7185")

    /// Fresh form (positive TSB) - soft green
    static let chartFormFresh = Color(hex: "34D399")

    /// Tired form (negative TSB) - soft coral
    static let chartFormTired = Color(hex: "F87171")

    // MARK: - Text Colors (Warmer Grays)

    /// Primary text - white
    static let textPrimary = Color.white

    /// Secondary text - warmer gray (Zinc-400)
    static let textSecondary = Color(hex: "A1A1AA")

    /// Tertiary text - darker gray (Zinc-600)
    static let textTertiary = Color(hex: "52525B")

    // MARK: - Border Colors

    /// Primary border - subtle
    static let borderPrimary = Color(white: 0.15)

    // MARK: - Semantic Gradients (Removed for Cleaner Look)
    // Single-color rings are now preferred over gradients

    /// Readiness ring gradient for high scores (kept for compatibility)
    static var readinessGradientHigh: LinearGradient {
        LinearGradient(
            colors: [statusOptimal, statusOptimal],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Readiness ring gradient for medium scores
    static var readinessGradientMedium: LinearGradient {
        LinearGradient(
            colors: [statusModerate, statusModerate],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Readiness ring gradient for low scores
    static var readinessGradientLow: LinearGradient {
        LinearGradient(
            colors: [statusLow, statusLow],
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
        case .fullyReady: return .statusOptimal
        case .mostlyReady: return .accentPrimary  // Amber gold for mostly ready
        case .reducedCapacity: return .statusModerate
        case .restRecommended: return .statusLow
        }
    }

    /// Returns the solid color for the readiness ring (no gradients for cleaner look)
    var ringColor: Color {
        themeColor
    }

    /// Returns the gradient for the readiness ring (kept for backwards compatibility)
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
        case 15...: return .chartFormFresh      // Very fresh - soft green
        case 5..<15: return .metricTertiary     // Fresh - teal
        case -10..<5: return .textSecondary     // Neutral - gray
        case -25..<(-10): return .statusModerate // Tired - amber
        default: return .statusLow              // Very tired - coral
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
    /// Color indicating data quality - green for best, amber for fallback
    var qualityColor: Color {
        switch qualityRank {
        case 3: return .statusOptimal    // Power - best quality
        case 2: return .metricPrimary    // Pace - good quality
        case 1: return .statusModerate   // HR - acceptable
        default: return .statusLow       // Estimated - lowest
        }
    }
}

// MARK: - Letter Grade System

/// Letter grade representation for readiness scores
struct LetterGrade {
    let grade: String
    let color: Color

    /// Returns letter grade for a 0-100 score
    static func from(score: Double) -> LetterGrade {
        let grade: String
        switch score {
        case 97...100: grade = "A+"
        case 93..<97: grade = "A"
        case 90..<93: grade = "A-"
        case 87..<90: grade = "B+"
        case 83..<87: grade = "B"
        case 80..<83: grade = "B-"
        case 77..<80: grade = "C+"
        case 73..<77: grade = "C"
        case 70..<73: grade = "C-"
        case 67..<70: grade = "D+"
        case 63..<67: grade = "D"
        case 60..<63: grade = "D-"
        default: grade = "F"
        }
        return LetterGrade(grade: grade, color: colorForGrade(grade))
    }

    /// Returns color for a letter grade
    static func colorForGrade(_ grade: String) -> Color {
        switch grade.prefix(1) {
        case "A": return .statusOptimal    // Green
        case "B": return .accentPrimary    // Gold/Amber
        case "C": return .statusModerate   // Orange
        case "D": return .statusLow        // Coral
        default: return Color(hex: "EF4444") // Red for F
        }
    }

    /// Returns status description for a letter grade
    var statusDescription: String {
        switch grade.prefix(1) {
        case "A": return "Excellent"
        case "B": return "Good"
        case "C": return "Average"
        case "D": return "Fair"
        default: return "Rest Needed"
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
