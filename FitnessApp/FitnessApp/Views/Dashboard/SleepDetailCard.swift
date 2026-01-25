import SwiftUI
import Charts

/// Card showing detailed sleep breakdown
struct SleepDetailCard: View {
    let sleepData: SleepData?
    let targetHours: Double = 8

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack {
                Image(systemName: "moon.fill")
                    .font(.system(size: IconSize.medium))
                    .foregroundStyle(Color.accentSecondary)
                Text("Sleep".uppercased())
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)

                Spacer()

                if let data = sleepData {
                    Text(String(format: "%.0f%%", data.qualityScore * 100))
                        .font(AppFont.labelMedium)
                        .padding(.horizontal, Spacing.xs)
                        .padding(.vertical, Spacing.xxs)
                        .background(qualityColor(data.qualityScore).opacity(0.2))
                        .foregroundStyle(qualityColor(data.qualityScore))
                        .clipShape(Capsule())
                }
            }

            if let data = sleepData {
                // Duration bar
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    HStack(spacing: Spacing.xs) {
                        Text(formatDuration(data.totalSleepHours))
                            .font(AppFont.metricMedium)
                            .foregroundStyle(Color.textPrimary)

                        Text("of \(Int(targetHours))h target")
                            .font(AppFont.captionLarge)
                            .foregroundStyle(Color.textTertiary)
                    }

                    // Progress bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.backgroundTertiary)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(durationColor(data.totalSleepHours))
                                .frame(width: min(geometry.size.width * (data.totalSleepHours / targetHours), geometry.size.width))
                        }
                    }
                    .frame(height: 8)
                }

                // Sleep stages breakdown
                if hasStageData(data) {
                    VStack(spacing: Spacing.xs) {
                        Divider()
                            .background(Color.backgroundTertiary)

                        // Stage bar
                        SleepStageBar(
                            deep: data.deepSleepMinutes,
                            rem: data.remSleepMinutes,
                            core: data.coreSleepMinutes,
                            awake: data.awakeMinutes
                        )

                        // Stage legend
                        HStack(spacing: Spacing.sm) {
                            StageLabel(color: .accentSecondary, label: "Deep", minutes: data.deepSleepMinutes)
                            StageLabel(color: .activitySwim, label: "REM", minutes: data.remSleepMinutes)
                            StageLabel(color: .chartFitness.opacity(0.6), label: "Core", minutes: data.coreSleepMinutes)
                            if data.awakeMinutes > 0 {
                                StageLabel(color: .statusModerate, label: "Awake", minutes: data.awakeMinutes)
                            }
                        }
                    }
                }

                // Efficiency
                if let efficiency = Optional(data.efficiency), efficiency > 0 {
                    HStack {
                        Text("Efficiency")
                            .font(AppFont.captionLarge)
                            .foregroundStyle(Color.textTertiary)
                        Spacer()
                        Text(String(format: "%.0f%%", efficiency * 100))
                            .font(AppFont.labelMedium)
                            .foregroundStyle(Color.textSecondary)
                    }
                }

                // Time in bed
                if let start = data.startTime, let end = data.endTime {
                    HStack {
                        Text("In bed")
                            .font(AppFont.captionLarge)
                            .foregroundStyle(Color.textTertiary)
                        Spacer()
                        Text("\(formatTime(start)) - \(formatTime(end))")
                            .font(AppFont.labelMedium)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            } else {
                // No data state
                VStack(spacing: Spacing.xs) {
                    Image(systemName: "moon.zzz")
                        .font(.system(size: IconSize.extraLarge))
                        .foregroundStyle(Color.textTertiary)
                    Text("No sleep data")
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.lg)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    private func qualityColor(_ score: Double) -> Color {
        switch score {
        case 0.8...: return .statusExcellent
        case 0.6..<0.8: return .statusGood
        case 0.4..<0.6: return .statusModerate
        default: return .statusLow
        }
    }

    private func durationColor(_ hours: Double) -> Color {
        switch hours {
        case 7...9: return .statusExcellent
        case 6..<7, 9..<10: return .statusGood
        default: return .statusModerate
        }
    }

    private func formatDuration(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func hasStageData(_ data: SleepData) -> Bool {
        data.deepSleepMinutes > 0 || data.remSleepMinutes > 0 || data.coreSleepMinutes > 0
    }
}

/// Horizontal stacked bar showing sleep stages
struct SleepStageBar: View {
    let deep: Double
    let rem: Double
    let core: Double
    let awake: Double

    private var total: Double {
        deep + rem + core + awake
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                if deep > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accentSecondary)
                        .frame(width: max(4, geometry.size.width * (deep / total)))
                }
                if rem > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.activitySwim)
                        .frame(width: max(4, geometry.size.width * (rem / total)))
                }
                if core > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.chartFitness.opacity(0.6))
                        .frame(width: max(4, geometry.size.width * (core / total)))
                }
                if awake > 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.statusModerate)
                        .frame(width: max(4, geometry.size.width * (awake / total)))
                }
            }
        }
        .frame(height: 12)
    }
}

/// Label for sleep stage with duration
struct StageLabel: View {
    let color: Color
    let label: String
    let minutes: Double

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text("\(Int(minutes))m")
                .font(AppFont.captionSmall)
                .foregroundStyle(Color.textTertiary)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            SleepDetailCard(
                sleepData: SleepData(
                    totalSleepHours: 7.5,
                    deepSleepMinutes: 85,
                    remSleepMinutes: 95,
                    coreSleepMinutes: 270,
                    awakeMinutes: 15,
                    efficiency: 0.92,
                    startTime: Calendar.current.date(bySettingHour: 22, minute: 30, second: 0, of: Date()),
                    endTime: Calendar.current.date(bySettingHour: 6, minute: 15, second: 0, of: Date())
                )
            )

            SleepDetailCard(
                sleepData: SleepData(
                    totalSleepHours: 5.5,
                    deepSleepMinutes: 45,
                    remSleepMinutes: 60,
                    coreSleepMinutes: 195,
                    awakeMinutes: 30,
                    efficiency: 0.78,
                    startTime: Calendar.current.date(bySettingHour: 0, minute: 30, second: 0, of: Date()),
                    endTime: Calendar.current.date(bySettingHour: 6, minute: 0, second: 0, of: Date())
                )
            )

            SleepDetailCard(sleepData: nil)
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}
