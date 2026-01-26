import SwiftUI

/// The centerpiece hero component showing training readiness with letter grades
/// Shows overall grade and breakdown of all 5 components (HRV, Sleep, RHR, Recovery, Form)
struct HeroReadinessRing: View {
    let score: Double
    let readiness: TrainingReadiness
    let components: ReadinessComponents
    let onTap: (() -> Void)?
    let onInfoTap: (() -> Void)?

    @State private var animatedProgress: Double = 0
    @State private var isAppeared = false

    // Convenience initializer for backwards compatibility
    init(
        score: Double,
        readiness: TrainingReadiness,
        hrvScore: Double? = nil,
        sleepScore: Double? = nil,
        rhrScore: Double? = nil,
        recoveryScore: Double? = nil,
        tsbScore: Double? = nil,
        onTap: (() -> Void)? = nil,
        onInfoTap: (() -> Void)? = nil
    ) {
        self.score = score
        self.readiness = readiness
        self.components = ReadinessComponents(
            hrvScore: hrvScore,
            sleepScore: sleepScore,
            rhrScore: rhrScore,
            recoveryScore: recoveryScore,
            stressScore: nil,
            tsbScore: tsbScore
        )
        self.onTap = onTap
        self.onInfoTap = onInfoTap
    }

    // Full initializer with ReadinessComponents
    init(
        score: Double,
        readiness: TrainingReadiness,
        components: ReadinessComponents,
        onTap: (() -> Void)? = nil,
        onInfoTap: (() -> Void)? = nil
    ) {
        self.score = score
        self.readiness = readiness
        self.components = components
        self.onTap = onTap
        self.onInfoTap = onInfoTap
    }

    private var overallGrade: LetterGrade {
        LetterGrade.from(score: score)
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            // Header with title and info button
            HStack {
                Text("READINESS")
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)

                Spacer()

                if onInfoTap != nil {
                    Button {
                        onInfoTap?()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: IconSize.medium))
                            .foregroundStyle(Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Main ring with letter grade
            ZStack {
                // Background ring - subtle
                Circle()
                    .stroke(
                        Color.backgroundTertiary,
                        style: StrokeStyle(lineWidth: Layout.heroRingStroke, lineCap: .round)
                    )

                // Animated progress ring
                Circle()
                    .trim(from: 0, to: animatedProgress / 100)
                    .stroke(
                        overallGrade.color,
                        style: StrokeStyle(lineWidth: Layout.heroRingStroke, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))

                // Center content - letter grade
                VStack(spacing: Spacing.xxxs) {
                    Text(overallGrade.grade)
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundStyle(overallGrade.color)
                        .contentTransition(.numericText())

                    Text("(\(Int(score)) / 100)")
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.textTertiary)

                    Text(readiness.rawValue.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(overallGrade.color)
                        .tracking(0.5)
                }
            }
            .frame(width: Layout.heroRingSize, height: Layout.heroRingSize)

            // Component breakdown with letter grades
            VStack(spacing: Spacing.xs) {
                if let hrv = components.hrvScore {
                    ComponentGradeRow(label: "HRV", score: hrv)
                }

                if let sleep = components.sleepScore {
                    ComponentGradeRow(label: "Sleep", score: sleep)
                }

                if let rhr = components.rhrScore {
                    ComponentGradeRow(label: "RHR", score: rhr)
                }

                if let recovery = components.recoveryScore {
                    ComponentGradeRow(label: "Recovery", score: recovery)
                }

                if let tsb = components.tsbScore {
                    ComponentGradeRow(label: "Form", score: tsb)
                }
            }
            .animatedAppearance(index: 1)
        }
        .padding(Spacing.md)
        .cardBackground(cornerRadius: CornerRadius.large)
        .onTapGesture {
            onTap?()
        }
        .onAppear {
            withAnimation(AppAnimation.springGentle.delay(0.2)) {
                animatedProgress = score
            }
            isAppeared = true
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Training readiness: \(overallGrade.grade), \(Int(score)) percent, \(readiness.rawValue)")
        .accessibilityHint("Tap for details")
    }
}

// MARK: - Component Grade Row

/// Horizontal bar showing metric with label, progress bar, and letter grade
private struct ComponentGradeRow: View {
    let label: String
    let score: Double

    private var grade: LetterGrade {
        LetterGrade.from(score: score)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Label
            Text(label)
                .font(AppFont.captionLarge)
                .foregroundStyle(Color.textTertiary)
                .frame(width: 60, alignment: .leading)

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.backgroundTertiary)

                    Capsule()
                        .fill(grade.color)
                        .frame(width: geometry.size.width * min(score / 100, 1))
                }
            }
            .frame(height: 6)

            // Letter grade (bold, colored)
            Text(grade.grade)
                .font(AppFont.labelMedium)
                .fontWeight(.semibold)
                .foregroundStyle(grade.color)
                .frame(width: 28, alignment: .trailing)
        }
    }
}

// MARK: - Legacy Support

/// Inline metric bar kept for compatibility - now uses letter grades internally
private struct InlineMetricBar: View {
    let label: String
    let score: Double
    let color: Color

    var body: some View {
        ComponentGradeRow(label: label, score: score)
    }
}

// MARK: - Preview

#Preview("All States") {
    ScrollView {
        VStack(spacing: Spacing.md) {
            HeroReadinessRing(
                score: 92,
                readiness: .fullyReady,
                hrvScore: 95,
                sleepScore: 91,
                rhrScore: 88,
                recoveryScore: 100,
                tsbScore: 85,
                onInfoTap: {}
            )

            HeroReadinessRing(
                score: 77,
                readiness: .mostlyReady,
                hrvScore: 82,
                sleepScore: 90,
                rhrScore: 75,
                recoveryScore: 70,
                tsbScore: 68,
                onInfoTap: {}
            )

            HeroReadinessRing(
                score: 55,
                readiness: .reducedCapacity,
                hrvScore: 55,
                sleepScore: 62,
                rhrScore: 50,
                recoveryScore: 60,
                tsbScore: 48,
                onInfoTap: {}
            )

            HeroReadinessRing(
                score: 35,
                readiness: .restRecommended,
                hrvScore: 30,
                sleepScore: 45,
                rhrScore: 35,
                recoveryScore: 40,
                tsbScore: 25,
                onInfoTap: {}
            )
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}

#Preview("Mostly Ready - C+") {
    HeroReadinessRing(
        score: 77,
        readiness: .mostlyReady,
        hrvScore: 87,
        sleepScore: 91,
        rhrScore: 85,
        recoveryScore: 78,
        tsbScore: 84,
        onInfoTap: {}
    )
    .padding()
    .background(Color.backgroundPrimary)
}
