import SwiftUI

/// A card displaying a single metric score with title, value, and trend
struct ScoreCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let trend: Trend?
    let trendValue: String?
    let color: Color
    let icon: String?

    init(
        title: String,
        value: String,
        subtitle: String? = nil,
        trend: Trend? = nil,
        trendValue: String? = nil,
        color: Color = .blue,
        icon: String? = nil
    ) {
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.trend = trend
        self.trendValue = trendValue
        self.color = color
        self.icon = icon
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with title and optional icon
            HStack {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)

                Spacer()

                if let icon {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundStyle(color)
                }
            }

            // Value
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(color)

            // Subtitle and trend
            HStack(spacing: 4) {
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let trend, let trendValue {
                    HStack(spacing: 2) {
                        Image(systemName: trend.icon)
                            .font(.caption2)
                        Text(trendValue)
                            .font(.caption2)
                    }
                    .foregroundStyle(trendColor(for: trend))
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func trendColor(for trend: Trend) -> Color {
        switch trend {
        case .up: return .green
        case .down: return .red
        case .stable: return .secondary
        }
    }
}

// MARK: - PMC Score Cards

/// Fitness (CTL) score card
struct FitnessCard: View {
    let ctl: Double
    let trend: Trend?
    let change: Double?

    var body: some View {
        ScoreCard(
            title: "Fitness",
            value: String(format: "%.0f", ctl),
            subtitle: "CTL",
            trend: trend,
            trendValue: change.map { String(format: "%+.1f", $0) },
            color: .blue,
            icon: "chart.line.uptrend.xyaxis"
        )
    }
}

/// Fatigue (ATL) score card
struct FatigueCard: View {
    let atl: Double
    let trend: Trend?
    let change: Double?

    var body: some View {
        ScoreCard(
            title: "Fatigue",
            value: String(format: "%.0f", atl),
            subtitle: "ATL",
            trend: trend,
            trendValue: change.map { String(format: "%+.1f", $0) },
            color: .pink,
            icon: "bolt.fill"
        )
    }
}

/// Form (TSB) score card
struct FormCard: View {
    let tsb: Double

    private var color: Color {
        switch tsb {
        case 15...: return .green
        case 5..<15: return .teal
        case -10..<5: return .blue
        case -25..<(-10): return .orange
        default: return .red
        }
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
        ScoreCard(
            title: "Form",
            value: String(format: "%+.0f", tsb),
            subtitle: status,
            color: color,
            icon: "figure.run"
        )
    }
}

// MARK: - Wellness Score Cards

/// HRV score card
struct HRVCard: View {
    let hrv: Double?
    let status: HRVStatus?
    let trend: Trend?

    private var color: Color {
        guard let status else { return .gray }
        switch status {
        case .elevated: return .green
        case .normal: return .blue
        case .belowNormal: return .orange
        case .low: return .red
        case .unknown: return .gray
        }
    }

    var body: some View {
        ScoreCard(
            title: "HRV",
            value: hrv.map { String(format: "%.0f", $0) } ?? "--",
            subtitle: status?.rawValue ?? "No data",
            trend: trend,
            color: color,
            icon: "waveform.path.ecg"
        )
    }
}

/// Resting HR score card
struct RestingHRCard: View {
    let rhr: Int?
    let status: RHRStatus?
    let baseline: Double?

    private var color: Color {
        guard let status else { return .gray }
        switch status {
        case .veryLow, .low: return .green
        case .normal: return .blue
        case .elevated: return .orange
        case .high: return .red
        case .unknown: return .gray
        }
    }

    var body: some View {
        let subtitle: String
        if let rhr, let baseline {
            let diff = Double(rhr) - baseline
            subtitle = String(format: "%+.0f vs avg", diff)
        } else {
            subtitle = status?.rawValue ?? "No data"
        }

        return ScoreCard(
            title: "Resting HR",
            value: rhr.map { "\($0)" } ?? "--",
            subtitle: subtitle,
            color: color,
            icon: "heart.fill"
        )
    }
}

/// Sleep score card
struct SleepCard: View {
    let hours: Double?
    let quality: SleepStatus?

    private var color: Color {
        guard let quality else { return .gray }
        switch quality {
        case .excellent: return .green
        case .good: return .blue
        case .fair: return .orange
        case .poor: return .red
        }
    }

    private var formattedHours: String {
        guard let hours else { return "--" }
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    var body: some View {
        ScoreCard(
            title: "Sleep",
            value: formattedHours,
            subtitle: quality?.rawValue ?? "No data",
            color: color,
            icon: "moon.fill"
        )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                FitnessCard(ctl: 72, trend: .up, change: 2.3)
                FatigueCard(atl: 85, trend: .up, change: 5.1)
                FormCard(tsb: -13)
            }

            HStack(spacing: 12) {
                HRVCard(hrv: 45, status: .normal, trend: .stable)
                SleepCard(hours: 7.5, quality: .good)
                RestingHRCard(rhr: 52, status: .normal, baseline: 50)
            }
        }
        .padding()
    }
}
