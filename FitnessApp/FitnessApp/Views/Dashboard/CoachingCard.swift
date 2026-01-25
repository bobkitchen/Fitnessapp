import SwiftUI

/// Top card showing AI coaching recommendation based on current state
struct CoachingCard: View {
    let readiness: TrainingReadiness
    let recommendation: String
    let suggestedWorkout: String?
    let onAskCoach: () -> Void

    @State private var isPressed = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack {
                Image(systemName: readinessIcon)
                    .font(.system(size: IconSize.large))
                    .foregroundStyle(readiness.themeColor)

                VStack(alignment: .leading, spacing: Spacing.xxxs) {
                    Text("Today's Training".uppercased())
                        .font(AppFont.labelSmall)
                        .foregroundStyle(Color.textTertiary)
                    Text(readiness.rawValue)
                        .font(AppFont.bodyLarge)
                        .fontWeight(.semibold)
                        .foregroundStyle(readiness.themeColor)
                }

                Spacer()

                // Readiness score circle
                ReadinessRing(readiness: readiness)
                    .frame(width: 50, height: 50)
            }

            // Recommendation
            Text(recommendation)
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(3)

            // Suggested workout
            if let workout = suggestedWorkout {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "figure.run")
                        .font(.system(size: IconSize.small))
                    Text(workout)
                        .font(AppFont.labelMedium)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(readiness.themeColor.opacity(0.15))
                .clipShape(Capsule())
                .foregroundStyle(readiness.themeColor)
            }

            // Ask Coach button
            Button(action: onAskCoach) {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: "sparkles")
                    Text("Ask AI Coach")
                }
                .font(AppFont.labelLarge)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.sm)
                .background(Color.accentSecondary.opacity(0.15))
                .foregroundStyle(Color.accentSecondary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
            }
            .buttonStyle(.plain)
        }
        .padding(Spacing.md)
        .background(
            LinearGradient(
                colors: [readiness.themeColor.opacity(0.08), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cardBackground()
    }

    private var readinessIcon: String {
        switch readiness {
        case .fullyReady: return "checkmark.circle.fill"
        case .mostlyReady: return "checkmark.circle"
        case .reducedCapacity: return "exclamationmark.triangle"
        case .restRecommended: return "bed.double.fill"
        }
    }
}

/// Circular ring showing readiness level
struct ReadinessRing: View {
    let readiness: TrainingReadiness

    @State private var animatedProgress: Double = 0

    private var targetProgress: Double {
        switch readiness {
        case .fullyReady: return 1.0
        case .mostlyReady: return 0.75
        case .reducedCapacity: return 0.5
        case .restRecommended: return 0.25
        }
    }

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(readiness.themeColor.opacity(0.2), lineWidth: 5)

            // Progress ring
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    readiness.themeColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

            // Percentage
            Text("\(Int(animatedProgress * 100))")
                .font(AppFont.labelLarge)
                .foregroundStyle(readiness.themeColor)
                .contentTransition(.numericText())
        }
        .onAppear {
            withAnimation(AppAnimation.springGentle) {
                animatedProgress = targetProgress
            }
        }
    }
}

/// Compact readiness indicator for smaller spaces
struct ReadinessIndicator: View {
    let score: Double

    private var readiness: TrainingReadiness {
        TrainingReadiness(score: score)
    }

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(readiness.themeColor)
                .frame(width: 8, height: 8)
            Text("\(Int(score))")
                .font(AppFont.labelMedium)
                .foregroundStyle(Color.textPrimary)
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            CoachingCard(
                readiness: .fullyReady,
                recommendation: "Your HRV is 15% above baseline and you're well rested. Great day for a quality workout or threshold intervals.",
                suggestedWorkout: "60min Zone 4 intervals",
                onAskCoach: {}
            )

            CoachingCard(
                readiness: .reducedCapacity,
                recommendation: "HRV is below baseline and sleep was limited. Consider an easy recovery session or rest.",
                suggestedWorkout: "30min easy spin",
                onAskCoach: {}
            )

            HStack(spacing: Spacing.md) {
                ReadinessRing(readiness: .fullyReady)
                ReadinessRing(readiness: .mostlyReady)
                ReadinessRing(readiness: .reducedCapacity)
                ReadinessRing(readiness: .restRecommended)
            }
            .frame(height: 60)
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}
