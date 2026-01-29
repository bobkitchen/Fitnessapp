import SwiftUI
import SwiftData

/// Main dashboard view showing training status, wellness, and activity
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService
    @Environment(ReadinessStateService.self) private var readinessState: ReadinessStateService?
    @Query(sort: [SortDescriptor(\DailyMetrics.date, order: .reverse)]) private var dailyMetrics: [DailyMetrics]
    @Query(sort: [SortDescriptor(\WorkoutRecord.startDate, order: .reverse)]) private var allWorkouts: [WorkoutRecord]

    /// Limit workouts to most recent 100 to prevent performance issues with large histories.
    /// This is computed from the query results since @Query doesn't support fetchLimit directly.
    private var recentWorkouts: [WorkoutRecord] {
        Array(allWorkouts.prefix(100))
    }
    @Query private var profiles: [AthleteProfile]

    // showingCoachSheet removed - Coach tab available in navigation
    // selectedDate removed - PMC chart moved to Performance tab
    @State private var syncService: WorkoutSyncService?
    @State private var stravaSyncService: StravaSyncService?
    @State private var hasPerformedInitialSync = false
    @State private var showReadinessDetail = false
    @State private var showGradeExplanation = false
    @State private var showingProfileSheet = false

    private var profile: AthleteProfile? { profiles.first }
    private var todayMetrics: DailyMetrics? {
        let today = Calendar.current.startOfDay(for: Date())
        return dailyMetrics.first { Calendar.current.isDate($0.date, inSameDayAs: today) }
    }

    private var last7DaysMetrics: [DailyMetrics] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        return dailyMetrics.filter { $0.date >= weekAgo }.sorted { $0.date < $1.date }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Layout.sectionSpacing) {
                    // Custom inline header (scrolls with content)
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: Spacing.xxxs) {
                            Text("Today")
                                .font(.system(size: 28, weight: .bold, design: .default))
                                .foregroundStyle(Color.textPrimary)
                            Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                                .font(AppFont.bodySmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                        Spacer()
                        ProfileAvatarButton(showingProfile: $showingProfileSheet, size: 40)
                    }
                    .padding(.bottom, Spacing.md)

                    // Hero Readiness Ring (single source of truth for readiness score)
                    heroReadinessSection
                        .animatedAppearance(index: 0)

                    // Section 1: Training Status & Recommendation
                    trainingStatusSection
                        .animatedAppearance(index: 1)

                    // Section 2: Activity (Recovery details moved to Performance tab)
                    activitySection
                        .animatedAppearance(index: 2)
                }
                .padding(Layout.screenPadding)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showingProfileSheet) {
                ProfileSheetView()
            }
            .sheet(isPresented: $showReadinessDetail) {
                if let result = calculateReadiness() {
                    ReadinessDetailSheet(result: result)
                }
            }
            .sheet(isPresented: $showGradeExplanation) {
                GradeExplanationSheet()
            }
            .refreshable {
                await refreshData()
            }
            .task {
                await performInitialSyncIfNeeded()
            }
            .overlay {
                if syncService?.isSyncing == true {
                    ProgressView("Syncing HealthKit data...")
                        .padding()
                        .cardBackground()
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Hero Readiness Section

    @ViewBuilder
    private var heroReadinessSection: some View {
        if let result = calculateReadiness() {
            HeroReadinessRing(
                score: result.score,
                readiness: result.readiness,
                components: result.components,
                onTap: { showReadinessDetail = true },
                onInfoTap: { showGradeExplanation = true }
            )
            // Single task handles both initial load and updates.
            // Using .id() on todayMetrics causes task to re-run when metrics change.
            .task(id: todayMetrics?.id) {
                updateReadinessState()
            }
        }
    }

    /// Single source of truth for updating the shared readiness state.
    /// Called from one place to avoid race conditions.
    private func updateReadinessState() {
        if let result = calculateReadiness() {
            readinessState?.currentScore = result.score
        }
    }

    // MARK: - Training Status Section

    @ViewBuilder
    private var trainingStatusSection: some View {
        // Use same calculated readiness as hero ring for consistency
        let readinessResult = calculateReadiness()
        let readiness = readinessResult?.readiness ?? .mostlyReady

        VStack(alignment: .leading, spacing: Layout.cardSpacing) {
            SectionHeader(title: "Training Status", icon: "chart.bar.fill")

            // Recommendation Card (formerly CoachingCard - redesigned without duplicate readiness)
            RecommendationCard(
                readiness: readiness,
                recommendation: generateRecommendation(for: readiness),
                suggestedWorkout: suggestWorkout(for: readiness)
            )

            // Compact Training Load Row (replaces 3 separate cards)
            TrainingLoadRow(
                ctl: todayMetrics?.ctl ?? 0,
                atl: todayMetrics?.atl ?? 0,
                tsb: todayMetrics?.tsb ?? 0,
                ctlTrend: ctlTrend,
                atlTrend: atlTrend
            )

            // PMC Mini Chart moved to Performance tab
        }
    }

    // MARK: - Recovery Section
    // Note: Detailed wellness metrics moved to Performance tab
    // Dashboard now focuses on actionable readiness info only

    // MARK: - Activity Section

    @ViewBuilder
    private var activitySection: some View {
        VStack(alignment: .leading, spacing: Layout.cardSpacing) {
            SectionHeader(title: "Activity", icon: "figure.run")

            // Recent Workouts
            RecentWorkoutsCard(workouts: Array(recentWorkouts.prefix(3)))

            // Weekly Summary
            WeeklySummaryCard(
                totalTSS: weeklyTSS,
                totalHours: weeklyHours,
                workoutCount: weeklyWorkoutCount,
                byActivity: weeklyByActivity
            )
        }
    }

    // MARK: - Computed Properties for Training Load Row

    private var ctlTrend: Trend? {
        guard last7DaysMetrics.count >= 2 else { return nil }
        let recent = last7DaysMetrics.suffix(2)
        let change = recent.last!.ctl - recent.first!.ctl
        if change > 1 { return .up }
        if change < -1 { return .down }
        return .stable
    }

    private var atlTrend: Trend? {
        guard last7DaysMetrics.count >= 2 else { return nil }
        let recent = last7DaysMetrics.suffix(2)
        let change = recent.last!.atl - recent.first!.atl
        if change > 2 { return .up }
        if change < -2 { return .down }
        return .stable
    }

    // MARK: - Wellness Baselines (delegating to TrainingRecommendationService)

    private var hrvBaseline: Double? {
        TrainingRecommendationService.calculateHRVBaseline(from: last7DaysMetrics)
    }

    private var rhrBaseline: Double? {
        TrainingRecommendationService.calculateRHRBaseline(from: last7DaysMetrics)
    }

    // MARK: - Weekly Activity Stats (delegating to TrainingRecommendationService)

    private var weeklyStats: (tss: Double, hours: Double, count: Int) {
        TrainingRecommendationService.calculateWeeklyStats(from: Array(recentWorkouts))
    }

    private var weeklyTSS: Double { weeklyStats.tss }
    private var weeklyHours: Double { weeklyStats.hours }
    private var weeklyWorkoutCount: Int { weeklyStats.count }

    private var weeklyByActivity: [ActivityCategory: Double] {
        TrainingRecommendationService.calculateWeeklyByActivity(from: Array(recentWorkouts))
    }

    // MARK: - Helper Methods (Delegating to TrainingRecommendationService)

    private func generateRecommendation(for readiness: TrainingReadiness) -> String {
        TrainingRecommendationService.generateRecommendation(
            for: readiness,
            hasMetrics: todayMetrics != nil
        )
    }

    private func suggestWorkout(for readiness: TrainingReadiness) -> String? {
        TrainingRecommendationService.suggestWorkout(
            for: readiness,
            hasMetrics: todayMetrics != nil
        )
    }

    private func calculateReadiness() -> ReadinessResult? {
        guard let metrics = todayMetrics else { return nil }

        // HRV Analysis using WellnessAnalyzer
        let hrvAnalysis: HRVAnalysis?
        if let hrv = metrics.hrvRMSSD {
            let baseline7Day = last7DaysMetrics.compactMap { $0.hrvRMSSD }
            hrvAnalysis = WellnessAnalyzer.analyzeHRV(
                currentHRV: hrv,
                baseline7Day: baseline7Day
            )
        } else {
            hrvAnalysis = nil
        }

        // Sleep Analysis
        let sleepAnalysis: SleepAnalysis?
        if let hours = metrics.sleepHours {
            sleepAnalysis = WellnessAnalyzer.analyzeSleep(
                hoursSlept: hours,
                sleepQuality: metrics.sleepQuality,
                deepSleepMinutes: metrics.deepSleepMinutes,
                remSleepMinutes: metrics.remSleepMinutes,
                efficiency: metrics.sleepEfficiency
            )
        } else {
            sleepAnalysis = nil
        }

        // RHR Analysis
        let rhrAnalysis: RHRAnalysis?
        if let rhr = metrics.restingHR {
            let baseline7Day = last7DaysMetrics.compactMap { $0.restingHR }.map { Double($0) }
            rhrAnalysis = WellnessAnalyzer.analyzeRestingHR(
                currentRHR: rhr,
                baseline7Day: baseline7Day
            )
        } else {
            rhrAnalysis = nil
        }

        // Calculate days since hard effort (TSS > 100 = hard workout)
        let hardWorkoutThreshold: Double = 100
        let daysSinceHardEffort = recentWorkouts
            .first { $0.tss >= hardWorkoutThreshold }
            .map { workout -> Int in
                let days = Calendar.current.dateComponents([.day], from: workout.startDate, to: Date()).day ?? 0
                return max(0, days)
            }

        // Get TSB (Form) from today's metrics
        let tsb = metrics.tsb

        // Use WellnessAnalyzer for weighted, comprehensive calculation
        return WellnessAnalyzer.calculateReadinessScore(
            hrvAnalysis: hrvAnalysis,
            sleepAnalysis: sleepAnalysis,
            rhrAnalysis: rhrAnalysis,
            daysSinceHardEffort: daysSinceHardEffort,
            tsb: tsb,
            mindfulMinutes: nil,
            stateOfMind: nil
        )
    }

    private func refreshData() async {
        // Sync HealthKit wellness data
        if syncService == nil {
            syncService = WorkoutSyncService(healthKitService: healthKitService)
        }
        await syncService?.performIncrementalSync(modelContext: modelContext, profile: profile)

        // Sync Strava workouts
        await stravaAutoSync()
    }

    private func performInitialSyncIfNeeded() async {
        guard !hasPerformedInitialSync else { return }

        // Wait for authorization if not yet authorized
        if !healthKitService.isAuthorized {
            try? await Task.sleep(for: .seconds(2))
            guard healthKitService.isAuthorized else { return }
        }

        hasPerformedInitialSync = true

        if syncService == nil {
            syncService = WorkoutSyncService(healthKitService: healthKitService)
        }

        // Check if we have any data yet
        if dailyMetrics.isEmpty && recentWorkouts.isEmpty {
            // Perform initial historical sync
            await syncService?.performInitialSync(modelContext: modelContext, profile: profile)
        } else {
            // Just do incremental sync
            await syncService?.performIncrementalSync(modelContext: modelContext, profile: profile)
        }

        // Auto-sync Strava workouts on launch
        await stravaAutoSync()
    }

    private func stravaAutoSync() async {
        let stravaService = StravaService()
        if stravaSyncService == nil {
            stravaSyncService = StravaSyncService(stravaService: stravaService, modelContext: modelContext)
        }
        await stravaSyncService?.autoSync()
    }
}

// MARK: - Section Header (Refined)

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: IconSize.small))
                .foregroundStyle(Color.accentPrimary)  // Amber gold accent
            Text(title.uppercased())
                .font(AppFont.labelSmall)
                .tracking(0.5)
                .foregroundStyle(Color.textSecondary)  // Slightly more visible
        }
    }
}

// MARK: - Recent Workouts Card (Refined with Left Accent Bars)

struct RecentWorkoutsCard: View {
    let workouts: [WorkoutRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recent Workouts".uppercased())
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)

            if workouts.isEmpty {
                Text("No recent workouts")
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Spacing.lg)
            } else {
                VStack(spacing: Spacing.sm) {  // Spacing instead of dividers
                    ForEach(workouts) { workout in
                        RefinedWorkoutRow(workout: workout)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
}

/// Refined workout row with left accent bar instead of icon background
struct RefinedWorkoutRow: View {
    let workout: WorkoutRecord

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 2)
                .fill(workout.activityCategory.themeColor)
                .frame(width: 3, height: 44)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(workout.title ?? workout.activityType)
                    .font(AppFont.bodyMedium)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)
                Text(workout.dateFormatted)
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            // Larger TSS display
            VStack(alignment: .trailing, spacing: Spacing.xxxs) {
                Text(String(format: "%.0f", workout.tss))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.textPrimary)
                Text("TSS")
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
            }
        }
    }
}

// Legacy WorkoutRow kept for compatibility
struct WorkoutRow: View {
    let workout: WorkoutRecord

    var body: some View {
        RefinedWorkoutRow(workout: workout)
    }
}

// MARK: - Weekly Summary Card (Refined with Hero TSS)

struct WeeklySummaryCard: View {
    let totalTSS: Double
    let totalHours: Double
    let workoutCount: Int
    let byActivity: [ActivityCategory: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("This Week".uppercased())
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)

            // Hero TSS number - largest, accent color
            HStack(alignment: .lastTextBaseline, spacing: Spacing.xs) {
                Text(String(format: "%.0f", totalTSS))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.accentPrimary)
                Text("TSS")
                    .font(AppFont.labelMedium)
                    .foregroundStyle(Color.textTertiary)
            }

            // Secondary metrics - smaller
            HStack(spacing: Spacing.xl) {
                CompactSummaryMetric(
                    value: String(format: "%.1f", totalHours),
                    unit: "hrs",
                    label: "Time"
                )
                CompactSummaryMetric(
                    value: "\(workoutCount)",
                    unit: nil,
                    label: "Workouts"
                )
            }

            // Activity breakdown - simplified, no icons
            if !byActivity.isEmpty {
                HStack(spacing: Spacing.md) {
                    ForEach(byActivity.sorted(by: { $0.value > $1.value }).prefix(3), id: \.key) { category, tss in
                        HStack(spacing: Spacing.xxs) {
                            Circle()
                                .fill(category.themeColor)
                                .frame(width: 6, height: 6)
                            Text("\(category.rawValue) \(String(format: "%.0f", tss))")
                                .font(AppFont.captionSmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
}

/// Compact metric for secondary stats in weekly summary
struct CompactSummaryMetric: View {
    let value: String
    let unit: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xxxs) {
            HStack(alignment: .lastTextBaseline, spacing: Spacing.xxs) {
                Text(value)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Color.textPrimary)
                if let unit {
                    Text(unit)
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            Text(label)
                .font(AppFont.captionSmall)
                .foregroundStyle(Color.textTertiary)
        }
    }
}

// Legacy SummaryMetric kept for compatibility
struct SummaryMetric: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: Spacing.xxxs) {
            Text(value)
                .font(AppFont.metricMedium)
                .foregroundStyle(color)
            Text(label)
                .font(AppFont.captionSmall)
                .foregroundStyle(Color.textTertiary)
        }
    }
}

// MARK: - Readiness Detail Sheet

struct ReadinessDetailSheet: View {
    let result: ReadinessResult
    @Environment(\.dismiss) private var dismiss

    private var overallGrade: LetterGrade {
        LetterGrade.from(score: result.score)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Large readiness display with letter grade
                    VStack(spacing: Spacing.sm) {
                        Text(overallGrade.grade)
                            .font(.system(size: 72, weight: .bold, design: .rounded))
                            .foregroundStyle(overallGrade.color)

                        Text("(\(Int(result.score)) / 100)")
                            .font(AppFont.bodyLarge)
                            .foregroundStyle(Color.textTertiary)

                        Text(result.readiness.rawValue)
                            .font(AppFont.titleMedium)
                            .foregroundStyle(Color.textSecondary)

                        Text(result.readiness.description)
                            .font(AppFont.bodyMedium)
                            .foregroundStyle(Color.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, Spacing.lg)

                    // Component breakdown with letter grades
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Components".uppercased())
                            .font(AppFont.labelSmall)
                            .foregroundStyle(Color.textTertiary)

                        if let hrv = result.components.hrvScore {
                            ComponentDetailRow(label: "HRV", score: hrv, icon: "waveform.path.ecg")
                        }
                        if let sleep = result.components.sleepScore {
                            ComponentDetailRow(label: "Sleep", score: sleep, icon: "moon.fill")
                        }
                        if let rhr = result.components.rhrScore {
                            ComponentDetailRow(label: "Resting HR", score: rhr, icon: "heart.fill")
                        }
                        if let recovery = result.components.recoveryScore {
                            ComponentDetailRow(label: "Recovery", score: recovery, icon: "arrow.counterclockwise")
                        }
                        if let tsb = result.components.tsbScore {
                            ComponentDetailRow(label: "Form", score: tsb, icon: "chart.line.uptrend.xyaxis")
                        }
                    }
                    .padding(Spacing.md)
                    .cardBackground()

                    // Insights
                    if !result.insights.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Insights".uppercased())
                                .font(AppFont.labelSmall)
                                .foregroundStyle(Color.textTertiary)

                            ForEach(result.insights, id: \.self) { insight in
                                HStack(alignment: .top, spacing: Spacing.xs) {
                                    Image(systemName: "lightbulb.fill")
                                        .font(.system(size: IconSize.small))
                                        .foregroundStyle(Color.statusModerate)
                                    Text(insight)
                                        .font(AppFont.bodySmall)
                                        .foregroundStyle(Color.textSecondary)
                                }
                            }
                        }
                        .padding(Spacing.md)
                        .cardBackground()
                    }
                }
                .padding(Layout.screenPadding)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Training Readiness")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentPrimary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct ComponentDetailRow: View {
    let label: String
    let score: Double
    let icon: String

    private var grade: LetterGrade {
        LetterGrade.from(score: score)
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: IconSize.medium))
                .foregroundStyle(grade.color)
                .frame(width: 30)

            Text(label)
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)

            Spacer()

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.backgroundTertiary)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(grade.color)
                        .frame(width: geometry.size.width * min(score / 100, 1))
                }
            }
            .frame(width: 80, height: 6)

            // Letter grade instead of numeric score
            Text(grade.grade)
                .font(AppFont.labelMedium)
                .fontWeight(.semibold)
                .foregroundStyle(grade.color)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Grade Explanation Sheet

/// Sheet explaining the letter grade system and what each component measures
struct GradeExplanationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Grade Scale Section
                    gradeScaleSection

                    // What Each Component Measures
                    componentExplanationsSection

                    // How to Improve Section
                    improvementTipsSection
                }
                .padding(Layout.screenPadding)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Understanding Your Score")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.accentPrimary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Grade Scale Section

    private var gradeScaleSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Grade Scale".uppercased())
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)

            VStack(spacing: Spacing.sm) {
                GradeScaleRow(grades: "A+ to A-", range: "90-100", description: "Excellent - You're well recovered", color: .statusOptimal)
                GradeScaleRow(grades: "B+ to B-", range: "80-89", description: "Good - Normal training appropriate", color: .accentPrimary)
                GradeScaleRow(grades: "C+ to C-", range: "70-79", description: "Average - Listen to your body", color: .statusModerate)
                GradeScaleRow(grades: "D+ to D-", range: "60-69", description: "Fair - Consider easier effort", color: .statusLow)
                GradeScaleRow(grades: "F", range: "<60", description: "Rest - Recovery needed", color: Color(hex: "EF4444"))
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    // MARK: - Component Explanations Section

    private var componentExplanationsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("What We Measure".uppercased())
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)

            VStack(spacing: Spacing.md) {
                ComponentExplanationRow(
                    icon: "waveform.path.ecg",
                    title: "HRV (30%)",
                    description: "Heart rate variability measures nervous system recovery. Higher is generally better.",
                    weight: "Most important recovery indicator"
                )

                ComponentExplanationRow(
                    icon: "moon.fill",
                    title: "Sleep (25%)",
                    description: "Sleep duration and quality. Aims for 7-9 hours with good deep and REM sleep.",
                    weight: "Critical for adaptation"
                )

                ComponentExplanationRow(
                    icon: "heart.fill",
                    title: "Resting HR (15%)",
                    description: "Lower resting heart rate indicates better cardiovascular recovery. Elevated = fatigue.",
                    weight: "Cardiovascular status"
                )

                ComponentExplanationRow(
                    icon: "arrow.counterclockwise",
                    title: "Recovery (15%)",
                    description: "Days since your last hard training session. More rest = better recovery.",
                    weight: "Accumulated fatigue"
                )

                ComponentExplanationRow(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Form / TSB (10%)",
                    description: "Training Stress Balance shows if you're fresh (positive) or fatigued (negative).",
                    weight: "Training load balance"
                )
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    // MARK: - Improvement Tips Section

    private var improvementTipsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("How to Improve".uppercased())
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ImprovementTip(text: "Maintain consistent sleep schedule")
                ImprovementTip(text: "Alternate hard and easy training days")
                ImprovementTip(text: "Stay hydrated and limit alcohol")
                ImprovementTip(text: "Manage stress with mindfulness")
                ImprovementTip(text: "Taper before important events")
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
}

// MARK: - Grade Scale Row

private struct GradeScaleRow: View {
    let grades: String
    let range: String
    let description: String
    let color: Color

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Text(grades)
                .font(AppFont.labelMedium)
                .fontWeight(.semibold)
                .foregroundStyle(color)
                .frame(width: 70, alignment: .leading)

            Text(range)
                .font(AppFont.captionLarge)
                .foregroundStyle(Color.textTertiary)
                .frame(width: 45, alignment: .leading)

            Text(description)
                .font(AppFont.captionLarge)
                .foregroundStyle(Color.textSecondary)
                .lineLimit(2)

            Spacer()
        }
    }
}

// MARK: - Component Explanation Row

private struct ComponentExplanationRow: View {
    let icon: String
    let title: String
    let description: String
    let weight: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: IconSize.medium))
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(title)
                    .font(AppFont.labelMedium)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)

                Text(description)
                    .font(AppFont.captionLarge)
                    .foregroundStyle(Color.textSecondary)
                    .lineSpacing(2)

                Text(weight)
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
                    .italic()
            }
        }
    }
}

// MARK: - Improvement Tip

private struct ImprovementTip: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: IconSize.small))
                .foregroundStyle(Color.statusOptimal)

            Text(text)
                .font(AppFont.bodySmall)
                .foregroundStyle(Color.textSecondary)
        }
    }
}

// MARK: - Preview

#Preview {
    DashboardView()
        .modelContainer(for: [
            AthleteProfile.self,
            DailyMetrics.self,
            WorkoutRecord.self
        ], inMemory: true)
        .environment(HealthKitService())
        .environment(ReadinessStateService())
}
