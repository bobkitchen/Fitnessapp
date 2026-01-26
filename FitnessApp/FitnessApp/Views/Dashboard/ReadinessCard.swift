import SwiftUI

/// Card showing readiness score with component breakdown
struct ReadinessCard: View {
    let result: ReadinessResult

    @State private var animatedScore: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header with score
            HStack {
                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text("Readiness".uppercased())
                        .font(AppFont.labelSmall)
                        .foregroundStyle(Color.textTertiary)
                        .tracking(0.5)

                    Text(result.readiness.rawValue)
                        .font(AppFont.bodyLarge)
                        .fontWeight(.semibold)
                        .foregroundStyle(result.readiness.themeColor)
                }

                Spacer()

                // Large score ring
                ZStack {
                    Circle()
                        .stroke(result.readiness.themeColor.opacity(0.2), lineWidth: 6)
                        .frame(width: 60, height: 60)

                    Circle()
                        .trim(from: 0, to: animatedScore / 100)
                        .stroke(
                            result.readiness.themeColor,
                            style: StrokeStyle(lineWidth: 6, lineCap: .round)
                        )
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 0) {
                        Text("\(Int(animatedScore))")
                            .font(AppFont.metricSmall)
                            .foregroundStyle(Color.textPrimary)
                            .contentTransition(.numericText())
                    }
                }
            }

            // Component breakdown
            VStack(spacing: Spacing.xs) {
                if let hrv = result.components.hrvScore {
                    ComponentRow(label: "HRV", score: hrv, icon: "waveform.path.ecg")
                }
                if let sleep = result.components.sleepScore {
                    ComponentRow(label: "Sleep", score: sleep, icon: "moon.fill")
                }
                if let rhr = result.components.rhrScore {
                    ComponentRow(label: "Resting HR", score: rhr, icon: "heart.fill")
                }
                if let recovery = result.components.recoveryScore {
                    ComponentRow(label: "Recovery", score: recovery, icon: "arrow.counterclockwise")
                }
            }

            // Insights
            if !result.insights.isEmpty {
                Divider()
                    .background(Color.backgroundTertiary)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(result.insights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: Spacing.xs) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: IconSize.small))
                                .foregroundStyle(Color.statusModerate)
                            Text(insight)
                                .font(AppFont.captionLarge)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
        .onAppear {
            withAnimation(AppAnimation.springGentle) {
                animatedScore = result.score
            }
        }
    }
}

/// Single component row in readiness breakdown
struct ComponentRow: View {
    let label: String
    let score: Double
    let icon: String

    private var color: Color {
        switch score {
        case 80...100: return .statusExcellent
        case 60..<80: return .statusGood
        case 40..<60: return .statusModerate
        default: return .statusLow
        }
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: IconSize.small))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 20)

            Text(label)
                .font(AppFont.captionLarge)
                .foregroundStyle(Color.textSecondary)

            Spacer()

            // Mini progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.backgroundTertiary)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geometry.size.width * min(score / 100, 1))
                }
            }
            .frame(width: 60, height: 4)

            Text("\(Int(score))")
                .font(AppFont.labelMedium)
                .foregroundStyle(color)
                .frame(width: 28, alignment: .trailing)
                .monospacedDigit()
        }
    }
}

// MARK: - Simplified Readiness Display

/// Compact readiness badge for use in lists or smaller contexts
struct ReadinessBadge: View {
    let score: Double

    private var readiness: TrainingReadiness {
        TrainingReadiness(score: score)
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Circle()
                .fill(readiness.themeColor)
                .frame(width: 10, height: 10)

            Text("\(Int(score))")
                .font(AppFont.labelLarge)
                .foregroundStyle(Color.textPrimary)

            Text(readiness.rawValue)
                .font(AppFont.captionLarge)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(.horizontal, Spacing.sm)
        .padding(.vertical, Spacing.xs)
        .background(readiness.themeColor.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            ReadinessCard(
                result: ReadinessResult(
                    score: 78,
                    readiness: .mostlyReady,
                    components: ReadinessComponents(
                        hrvScore: 82,
                        sleepScore: 75,
                        rhrScore: 70,
                        recoveryScore: 85,
                        stressScore: 65,
                        tsbScore: 70
                    ),
                    insights: [
                        "HRV is slightly above baseline",
                        "Good sleep duration but limited deep sleep"
                    ]
                )
            )

            ReadinessCard(
                result: ReadinessResult(
                    score: 45,
                    readiness: .reducedCapacity,
                    components: ReadinessComponents(
                        hrvScore: 40,
                        sleepScore: 55,
                        rhrScore: 45,
                        recoveryScore: 40,
                        stressScore: 50,
                        tsbScore: 45
                    ),
                    insights: [
                        "HRV is 20% below baseline - recovery needed",
                        "Consider a rest day or easy recovery session"
                    ]
                )
            )

            HStack(spacing: Spacing.sm) {
                ReadinessBadge(score: 85)
                ReadinessBadge(score: 62)
                ReadinessBadge(score: 38)
            }
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}
