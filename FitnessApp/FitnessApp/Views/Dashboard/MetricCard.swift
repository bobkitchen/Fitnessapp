import SwiftUI

/// A redesigned metric card with sparkline and trend indicator
struct DashboardMetricCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let trend: Trend?
    let trendValue: String?
    let color: Color
    let icon: String?
    let sparklineData: [Double]?

    @State private var isPressed = false

    init(
        title: String,
        value: String,
        subtitle: String? = nil,
        trend: Trend? = nil,
        trendValue: String? = nil,
        color: Color = .accentPrimary,
        icon: String? = nil,
        sparklineData: [Double]? = nil
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.trend = trend
        self.trendValue = trendValue
        self.color = color
        self.icon = icon
        self.sparklineData = sparklineData
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header with title and trend
            HStack {
                Text(title.uppercased())
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                if let trend {
                    Image(systemName: trend.icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(trendColor(for: trend))
                }
            }

            // Main value
            Text(value)
                .font(AppFont.metricLarge)
                .foregroundStyle(color)
                .contentTransition(.numericText())

            // Subtitle
            if let subtitle {
                Text(subtitle)
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
            }

            // Sparkline
            if let data = sparklineData, !data.isEmpty {
                SparklineView(data: data, color: color, showGradient: true)
                    .frame(height: 24)
                    .padding(.top, Spacing.xxs)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
        .scaleEffect(isPressed ? 0.98 : 1)
        .animation(AppAnimation.springSnappy, value: isPressed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
        .accessibilityValue(subtitle ?? "")
    }

    private func trendColor(for trend: Trend) -> Color {
        switch trend {
        case .up: return .statusExcellent
        case .down: return .statusLow
        case .stable: return .textTertiary
        }
    }
}

// MARK: - Specialized PMC Cards

/// Fitness (CTL) metric card
struct FitnessMetricCard: View {
    let ctl: Double
    let trend: Trend?
    let change: Double?
    let history: [Double]?

    var body: some View {
        DashboardMetricCard(
            title: "Fitness",
            value: String(format: "%.0f", ctl),
            subtitle: "CTL",
            trend: trend,
            trendValue: change.map { String(format: "%+.1f", $0) },
            color: .chartFitness,
            sparklineData: history
        )
    }
}

/// Fatigue (ATL) metric card
struct FatigueMetricCard: View {
    let atl: Double
    let trend: Trend?
    let change: Double?
    let history: [Double]?

    var body: some View {
        DashboardMetricCard(
            title: "Fatigue",
            value: String(format: "%.0f", atl),
            subtitle: "ATL",
            trend: trend,
            trendValue: change.map { String(format: "%+.1f", $0) },
            color: .chartFatigue,
            sparklineData: history
        )
    }
}

/// Form (TSB) metric card
struct FormMetricCard: View {
    let tsb: Double
    let history: [Double]?

    private var color: Color {
        Color.forTSB(tsb)
    }

    private var status: String {
        switch tsb {
        case 15...: return "Very Fresh"
        case 5..<15: return "Fresh"
        case -10..<5: return "Neutral"
        case -25..<(-10): return "Tired"
        default: return "Very Tired"
        }
    }

    var body: some View {
        DashboardMetricCard(
            title: "Form",
            value: String(format: "%+.0f", tsb),
            subtitle: status,
            color: color,
            sparklineData: history
        )
    }
}

// MARK: - Wellness Metric Cards

/// HRV metric card
struct HRVMetricCard: View {
    let hrv: Double?
    let status: HRVStatus?
    let trend: Trend?
    let history: [Double]?

    private var color: Color {
        guard let status else { return .textTertiary }
        switch status {
        case .elevated: return .statusExcellent
        case .normal: return .statusGood
        case .belowNormal: return .statusModerate
        case .low: return .statusLow
        case .unknown: return .textTertiary
        }
    }

    var body: some View {
        DashboardMetricCard(
            title: "HRV",
            value: hrv.map { String(format: "%.0f", $0) } ?? "--",
            subtitle: status?.rawValue ?? "No data",
            trend: trend,
            color: color,
            sparklineData: history
        )
    }
}

/// Sleep metric card
struct SleepMetricCard: View {
    let hours: Double?
    let quality: SleepStatus?
    let history: [Double]?

    private var color: Color {
        guard let quality else { return .textTertiary }
        switch quality {
        case .excellent: return .statusExcellent
        case .good: return .statusGood
        case .fair: return .statusModerate
        case .poor: return .statusLow
        }
    }

    private var formattedHours: String {
        guard let hours else { return "--" }
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    var body: some View {
        DashboardMetricCard(
            title: "Sleep",
            value: formattedHours,
            subtitle: quality?.rawValue ?? "No data",
            color: color,
            sparklineData: history
        )
    }
}

/// Resting HR metric card
struct RestingHRMetricCard: View {
    let rhr: Int?
    let status: RHRStatus?
    let baseline: Double?
    let history: [Double]?

    private var color: Color {
        guard let status else { return .textTertiary }
        switch status {
        case .veryLow, .low: return .statusExcellent
        case .normal: return .statusGood
        case .elevated: return .statusModerate
        case .high: return .statusLow
        case .unknown: return .textTertiary
        }
    }

    private var subtitle: String {
        if let rhr, let baseline {
            let diff = Double(rhr) - baseline
            return String(format: "%+.0f vs avg", diff)
        }
        return status?.rawValue ?? "No data"
    }

    var body: some View {
        DashboardMetricCard(
            title: "Resting HR",
            value: rhr.map { "\($0)" } ?? "--",
            subtitle: subtitle,
            color: color,
            sparklineData: history
        )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: Spacing.md) {
            // PMC cards
            HStack(spacing: Spacing.sm) {
                FitnessMetricCard(
                    ctl: 72,
                    trend: .up,
                    change: 2.3,
                    history: [68, 69, 70, 71, 71, 72, 72]
                )

                FatigueMetricCard(
                    atl: 85,
                    trend: .down,
                    change: -3.2,
                    history: [90, 88, 87, 86, 85, 85, 85]
                )

                FormMetricCard(
                    tsb: -13,
                    history: [-18, -17, -15, -14, -13, -13, -13]
                )
            }

            // Wellness cards
            HStack(spacing: Spacing.sm) {
                HRVMetricCard(
                    hrv: 45,
                    status: .normal,
                    trend: .up,
                    history: [40, 42, 43, 44, 44, 45, 45]
                )

                SleepMetricCard(
                    hours: 7.5,
                    quality: .good,
                    history: [7.0, 7.2, 6.8, 7.5, 7.3, 7.5, 7.5]
                )

                RestingHRMetricCard(
                    rhr: 52,
                    status: .normal,
                    baseline: 50,
                    history: [51, 52, 51, 52, 52, 52, 52]
                )
            }

            // Generic card
            DashboardMetricCard(
                title: "Custom",
                value: "123",
                subtitle: "Units",
                trend: .stable,
                color: .accentSecondary,
                sparklineData: [100, 110, 105, 115, 120, 118, 123]
            )
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}
