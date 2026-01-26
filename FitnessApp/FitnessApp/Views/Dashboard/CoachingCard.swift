import SwiftUI

/// Sport type for filtering recommendations
enum SportFilter: String, CaseIterable {
    case all = "All"
    case run = "Run"
    case bike = "Bike"
    case swim = "Swim"

    var icon: String {
        switch self {
        case .all: return "figure.mixed.cardio"
        case .run: return "figure.run"
        case .bike: return "bicycle"
        case .swim: return "figure.pool.swim"
        }
    }

    var color: Color {
        switch self {
        case .all: return .accentPrimary
        case .run: return .activityRun
        case .bike: return .activityBike
        case .swim: return .activitySwim
        }
    }
}

/// Recommendation card showing actionable training guidance
/// Refined: Larger text, softer divider, smaller sport pills
struct RecommendationCard: View {
    let readiness: TrainingReadiness
    let recommendation: String
    let suggestedWorkout: String?

    @State private var selectedSport: SportFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header - readiness label removed (shown in hero card)
            HStack {
                Image(systemName: readinessIcon)
                    .font(.system(size: IconSize.large))
                    .foregroundStyle(readiness.themeColor)

                Text("Today's Training".uppercased())
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)

                Spacer()
            }

            // Main recommendation text - larger font (17pt)
            Text(sportSpecificRecommendation)
                .font(.system(size: 17))
                .foregroundStyle(Color.textSecondary)
                .lineLimit(4)
                .lineSpacing(2)

            // Suggested workout based on selected sport
            if let workout = sportSpecificWorkout {
                HStack(spacing: Spacing.xs) {
                    Image(systemName: selectedSport.icon)
                        .font(.system(size: IconSize.small))
                    Text(workout)
                        .font(AppFont.labelMedium)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xs)
                .background(readiness.themeColor.opacity(0.12))
                .clipShape(Capsule())
                .foregroundStyle(readiness.themeColor)
            }

            // Softer divider (barely visible)
            Rectangle()
                .fill(Color.white.opacity(0.05))
                .frame(height: 1)
                .padding(.vertical, Spacing.xxs)

            // Refined sport toggle buttons - more compact
            HStack(spacing: Spacing.xs) {
                ForEach(SportFilter.allCases, id: \.self) { sport in
                    RefinedSportToggle(
                        sport: sport,
                        isSelected: selectedSport == sport,
                        onTap: { selectedSport = sport }
                    )
                }
                Spacer()
            }
        }
        .padding(Spacing.md)
        .background(
            LinearGradient(
                colors: [readiness.themeColor.opacity(0.06), Color.clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cardBackground()
    }

    // MARK: - Computed Properties

    private var readinessIcon: String {
        switch readiness {
        case .fullyReady: return "checkmark.circle.fill"
        case .mostlyReady: return "checkmark.circle"
        case .reducedCapacity: return "exclamationmark.triangle"
        case .restRecommended: return "bed.double.fill"
        }
    }

    /// Returns sport-specific recommendation text
    private var sportSpecificRecommendation: String {
        switch selectedSport {
        case .all:
            return recommendation
        case .run:
            return sportifyRecommendation(for: .run)
        case .bike:
            return sportifyRecommendation(for: .bike)
        case .swim:
            return sportifyRecommendation(for: .swim)
        }
    }

    /// Returns sport-specific workout suggestion
    private var sportSpecificWorkout: String? {
        guard let baseWorkout = suggestedWorkout else { return nil }

        switch selectedSport {
        case .all:
            return baseWorkout
        case .run:
            return runWorkoutSuggestion
        case .bike:
            return bikeWorkoutSuggestion
        case .swim:
            return swimWorkoutSuggestion
        }
    }

    private func sportifyRecommendation(for sport: SportFilter) -> String {
        switch readiness {
        case .fullyReady:
            switch sport {
            case .run: return "Great day for quality running. Try threshold intervals or a tempo run to push your fitness."
            case .bike: return "Excellent recovery - perfect for hard intervals or a challenging group ride."
            case .swim: return "Your body is ready. Consider a technique-focused session with some speed work."
            case .all: return recommendation
            }
        case .mostlyReady:
            switch sport {
            case .run: return "Good day for a moderate run. Steady aerobic effort will build your base."
            case .bike: return "Normal training is appropriate. Consider an endurance ride at tempo pace."
            case .swim: return "Standard swim session works well today. Focus on consistent pacing."
            case .all: return recommendation
            }
        case .reducedCapacity:
            switch sport {
            case .run: return "Keep it easy today. An easy jog or walk-run intervals would be ideal."
            case .bike: return "Recovery spin recommended. Keep the effort low and legs moving."
            case .swim: return "Easy swim with focus on form. Let the water do the work today."
            case .all: return recommendation
            }
        case .restRecommended:
            switch sport {
            case .run: return "Rest day advised. If you must move, a gentle walk is the maximum."
            case .bike: return "Skip the bike today. Your body needs recovery, not training stress."
            case .swim: return "Rest is best. If you need movement, very easy pool time only."
            case .all: return recommendation
            }
        }
    }

    private var runWorkoutSuggestion: String? {
        switch readiness {
        case .fullyReady: return "45min tempo run or 6x800m intervals"
        case .mostlyReady: return "45-60min easy to moderate run"
        case .reducedCapacity: return "20-30min easy jog"
        case .restRecommended: return "Rest or gentle walk"
        }
    }

    private var bikeWorkoutSuggestion: String? {
        switch readiness {
        case .fullyReady: return "60min with threshold intervals"
        case .mostlyReady: return "60-90min endurance ride"
        case .reducedCapacity: return "30-45min recovery spin"
        case .restRecommended: return "Rest day"
        }
    }

    private var swimWorkoutSuggestion: String? {
        switch readiness {
        case .fullyReady: return "2500m with speed sets"
        case .mostlyReady: return "2000m steady aerobic"
        case .reducedCapacity: return "1500m easy technique"
        case .restRecommended: return "Rest or 1000m very easy"
        }
    }
}

/// Refined sport toggle - more compact, smaller pills
struct RefinedSportToggle: View {
    let sport: SportFilter
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Spacing.xxs) {
                Image(systemName: sport.icon)
                    .font(.system(size: 12))
                Text(sport.rawValue)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, Spacing.xs)
            .padding(.vertical, Spacing.xxs + 2)
            .background(isSelected ? sport.color.opacity(0.15) : Color.backgroundTertiary.opacity(0.5))
            .foregroundStyle(isSelected ? sport.color : Color.textTertiary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Legacy sport toggle button for filtering recommendations
struct SportToggleButton: View {
    let sport: SportFilter
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        RefinedSportToggle(sport: sport, isSelected: isSelected, onTap: onTap)
    }
}

/// Legacy ReadinessRing kept for backwards compatibility (not used on dashboard)
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
            Circle()
                .stroke(readiness.themeColor.opacity(0.2), lineWidth: 5)

            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    readiness.themeColor,
                    style: StrokeStyle(lineWidth: 5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))

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
            RecommendationCard(
                readiness: .fullyReady,
                recommendation: "Your HRV is 15% above baseline and you're well rested. Great day for a quality workout or threshold intervals.",
                suggestedWorkout: "60min Zone 4 intervals"
            )

            RecommendationCard(
                readiness: .mostlyReady,
                recommendation: "Good recovery status. Normal training is appropriate today.",
                suggestedWorkout: "Moderate endurance session"
            )

            RecommendationCard(
                readiness: .reducedCapacity,
                recommendation: "HRV is below baseline and sleep was limited. Consider an easy recovery session or rest.",
                suggestedWorkout: "30min easy spin"
            )

            RecommendationCard(
                readiness: .restRecommended,
                recommendation: "Recovery indicators suggest rest is needed. Take a day off or do very light activity.",
                suggestedWorkout: "Rest day or yoga"
            )
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}
