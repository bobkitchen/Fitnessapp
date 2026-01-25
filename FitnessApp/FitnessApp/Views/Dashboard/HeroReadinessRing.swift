import SwiftUI

/// The centerpiece hero component showing training readiness as an animated ring
struct HeroReadinessRing: View {
    let score: Double
    let readiness: TrainingReadiness
    let hrvScore: Double?
    let sleepScore: Double?
    let onTap: (() -> Void)?

    @State private var animatedProgress: Double = 0
    @State private var isAppeared = false

    init(
        score: Double,
        readiness: TrainingReadiness,
        hrvScore: Double? = nil,
        sleepScore: Double? = nil,
        onTap: (() -> Void)? = nil
    ) {
        self.score = score
        self.readiness = readiness
        self.hrvScore = hrvScore
        self.sleepScore = sleepScore
        self.onTap = onTap
    }

    var body: some View {
        VStack(spacing: Spacing.lg) {
            // Main ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(
                        Color.backgroundTertiary,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )

                // Animated progress ring
                Circle()
                    .trim(from: 0, to: animatedProgress / 100)
                    .stroke(
                        ringGradient,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ringColor.opacity(0.4), radius: 8, x: 0, y: 4)

                // Center content
                VStack(spacing: Spacing.xxs) {
                    Text("\(Int(score))")
                        .font(AppFont.metricHero)
                        .foregroundStyle(Color.textPrimary)
                        .contentTransition(.numericText())

                    Text(readiness.rawValue.uppercased())
                        .font(AppFont.labelSmall)
                        .foregroundStyle(ringColor)
                        .tracking(1)
                }
            }
            .frame(width: Layout.heroRingSize, height: Layout.heroRingSize)
            .pulsingGlow(color: ringColor, radius: score >= 80 ? 12 : 0)

            // Component breakdown
            HStack(spacing: Spacing.xl) {
                if let hrv = hrvScore {
                    ComponentIndicator(
                        label: "HRV",
                        score: hrv,
                        color: colorForScore(hrv)
                    )
                }

                if let sleep = sleepScore {
                    ComponentIndicator(
                        label: "Sleep",
                        score: sleep,
                        color: colorForScore(sleep)
                    )
                }
            }
            .animatedAppearance(index: 1)
        }
        .padding(Spacing.lg)
        .cardBackground(cornerRadius: CornerRadius.extraLarge)
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
        .accessibilityLabel("Training readiness: \(Int(score)) percent, \(readiness.rawValue)")
        .accessibilityHint("Tap for details")
    }

    // MARK: - Computed Properties

    private var ringColor: Color {
        readiness.themeColor
    }

    private var ringGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: gradientColors),
            center: .center,
            startAngle: .degrees(-90),
            endAngle: .degrees(270)
        )
    }

    private var gradientColors: [Color] {
        switch readiness {
        case .fullyReady:
            return [Color.statusExcellent, Color.statusGood]
        case .mostlyReady:
            return [Color.statusGood, Color.chartFitness]
        case .reducedCapacity:
            return [Color.statusModerate, Color(hex: "FF8F00")]
        case .restRecommended:
            return [Color.statusLow, Color(hex: "D32F2F")]
        }
    }

    private func colorForScore(_ score: Double) -> Color {
        switch score {
        case 80...: return .statusExcellent
        case 60..<80: return .statusGood
        case 40..<60: return .statusModerate
        default: return .statusLow
        }
    }
}

// MARK: - Component Indicator

private struct ComponentIndicator: View {
    let label: String
    let score: Double
    let color: Color

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            // Mini progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.backgroundTertiary)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color)
                        .frame(width: geometry.size.width * (score / 100))
                }
            }
            .frame(width: 60, height: 4)

            HStack(spacing: Spacing.xxs) {
                Text(label)
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)

                Text("\(Int(score))")
                    .font(AppFont.labelMedium)
                    .foregroundStyle(Color.textSecondary)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: Spacing.lg) {
            HeroReadinessRing(
                score: 85,
                readiness: .fullyReady,
                hrvScore: 82,
                sleepScore: 88
            )

            HeroReadinessRing(
                score: 68,
                readiness: .mostlyReady,
                hrvScore: 65,
                sleepScore: 72
            )

            HeroReadinessRing(
                score: 45,
                readiness: .reducedCapacity,
                hrvScore: 40,
                sleepScore: 52
            )

            HeroReadinessRing(
                score: 28,
                readiness: .restRecommended,
                hrvScore: 25,
                sleepScore: 30
            )
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}
