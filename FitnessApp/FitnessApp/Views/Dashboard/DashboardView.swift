import SwiftUI
import SwiftData

/// Main dashboard view showing training status, wellness, and activity
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService
    @Query(sort: [SortDescriptor(\DailyMetrics.date, order: .reverse)]) private var dailyMetrics: [DailyMetrics]
    @Query(sort: [SortDescriptor(\WorkoutRecord.startDate, order: .reverse)]) private var recentWorkouts: [WorkoutRecord]
    @Query private var profiles: [AthleteProfile]

    @State private var showingCoachSheet = false
    @State private var selectedDate = Date()
    @State private var syncService: WorkoutSyncService?
    @State private var hasPerformedInitialSync = false
    @State private var showReadinessDetail = false

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
                    // Hero Readiness Ring
                    heroReadinessSection
                        .animatedAppearance(index: 0)

                    // Section 1: Training Status
                    trainingStatusSection
                        .animatedAppearance(index: 1)

                    // Section 2: Recovery & Wellness
                    recoverySection
                        .animatedAppearance(index: 2)

                    // Section 3: Activity
                    activitySection
                        .animatedAppearance(index: 3)
                }
                .padding(Layout.screenPadding)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Dashboard")
            .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingCoachSheet = true
                    } label: {
                        Image(systemName: "bubble.left.fill")
                            .foregroundStyle(Color.accentSecondary)
                    }
                }
            }
            .sheet(isPresented: $showingCoachSheet) {
                CoachView()
            }
            .sheet(isPresented: $showReadinessDetail) {
                if let result = calculateReadiness() {
                    ReadinessDetailSheet(result: result)
                }
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
                hrvScore: result.components.hrvScore,
                sleepScore: result.components.sleepScore,
                onTap: { showReadinessDetail = true }
            )
        }
    }

    // MARK: - Training Status Section

    @ViewBuilder
    private var trainingStatusSection: some View {
        VStack(alignment: .leading, spacing: Layout.cardSpacing) {
            SectionHeader(title: "Training Status", icon: "chart.bar.fill")

            // Coaching Card
            CoachingCard(
                readiness: todayMetrics?.trainingReadiness ?? .mostlyReady,
                recommendation: generateRecommendation(),
                suggestedWorkout: suggestWorkout(),
                onAskCoach: { showingCoachSheet = true }
            )

            // PMC Metric Cards with Sparklines
            HStack(spacing: Layout.cardSpacing) {
                FitnessMetricCard(
                    ctl: todayMetrics?.ctl ?? 0,
                    trend: ctlTrend,
                    change: ctlChange,
                    history: ctlHistory
                )
                FatigueMetricCard(
                    atl: todayMetrics?.atl ?? 0,
                    trend: atlTrend,
                    change: atlChange,
                    history: atlHistory
                )
                FormMetricCard(
                    tsb: todayMetrics?.tsb ?? 0,
                    history: tsbHistory
                )
            }

            // PMC Mini Chart
            PMCMiniChart(
                data: pmcDataPoints,
                selectedDate: selectedDate,
                onSelectDate: { date in selectedDate = date }
            )
        }
    }

    // MARK: - Recovery Section

    @ViewBuilder
    private var recoverySection: some View {
        VStack(alignment: .leading, spacing: Layout.cardSpacing) {
            SectionHeader(title: "Recovery & Wellness", icon: "heart.fill")

            // Wellness Metric Cards with Sparklines
            HStack(spacing: Layout.cardSpacing) {
                HRVMetricCard(
                    hrv: todayMetrics?.hrvRMSSD,
                    status: hrvStatus,
                    trend: hrvTrend,
                    history: hrvHistory
                )
                SleepMetricCard(
                    hours: todayMetrics?.sleepHours,
                    quality: sleepStatus,
                    history: sleepHistory
                )
                RestingHRMetricCard(
                    rhr: todayMetrics?.restingHR,
                    status: rhrStatus,
                    baseline: rhrBaseline,
                    history: rhrHistory
                )
            }

            // Sleep Detail
            SleepDetailCard(sleepData: todaySleepData)

            // Wellness Trends
            WellnessTrendsChart(
                hrvData: hrvTrendData,
                rhrData: rhrTrendData
            )
        }
    }

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

    // MARK: - Computed Properties

    private var pmcDataPoints: [PMCDataPoint] {
        last7DaysMetrics.map { metrics in
            PMCDataPoint(
                date: metrics.date,
                tss: metrics.totalTSS,
                ctl: metrics.ctl,
                atl: metrics.atl,
                tsb: metrics.tsb
            )
        }
    }

    // MARK: - Sparkline History Data

    private var ctlHistory: [Double] {
        last7DaysMetrics.map { $0.ctl }
    }

    private var atlHistory: [Double] {
        last7DaysMetrics.map { $0.atl }
    }

    private var tsbHistory: [Double] {
        last7DaysMetrics.map { $0.tsb }
    }

    private var hrvHistory: [Double] {
        last7DaysMetrics.compactMap { $0.hrvRMSSD }
    }

    private var sleepHistory: [Double] {
        last7DaysMetrics.compactMap { $0.sleepHours }
    }

    private var rhrHistory: [Double] {
        last7DaysMetrics.compactMap { $0.restingHR }.map { Double($0) }
    }

    private var ctlTrend: Trend? {
        guard last7DaysMetrics.count >= 2 else { return nil }
        let recent = last7DaysMetrics.suffix(2)
        let change = recent.last!.ctl - recent.first!.ctl
        if change > 1 { return .up }
        if change < -1 { return .down }
        return .stable
    }

    private var ctlChange: Double? {
        guard last7DaysMetrics.count >= 2 else { return nil }
        let recent = last7DaysMetrics.suffix(2)
        return recent.last!.ctl - recent.first!.ctl
    }

    private var atlTrend: Trend? {
        guard last7DaysMetrics.count >= 2 else { return nil }
        let recent = last7DaysMetrics.suffix(2)
        let change = recent.last!.atl - recent.first!.atl
        if change > 2 { return .up }
        if change < -2 { return .down }
        return .stable
    }

    private var atlChange: Double? {
        guard last7DaysMetrics.count >= 2 else { return nil }
        let recent = last7DaysMetrics.suffix(2)
        return recent.last!.atl - recent.first!.atl
    }

    private var hrvStatus: HRVStatus? {
        guard let hrv = todayMetrics?.hrvRMSSD else { return nil }
        let baseline = hrvBaseline ?? 45
        let percent = hrv / baseline
        switch percent {
        case 1.1...: return .elevated
        case 0.9..<1.1: return .normal
        case 0.8..<0.9: return .belowNormal
        default: return .low
        }
    }

    private var hrvTrend: Trend? {
        guard hrvTrendData.count >= 3 else { return nil }
        let recent = Array(hrvTrendData.suffix(3))
        let avg = recent.map(\.value).reduce(0, +) / Double(recent.count)
        let older = Array(hrvTrendData.prefix(4))
        let olderAvg = older.map(\.value).reduce(0, +) / Double(older.count)
        if avg > olderAvg * 1.05 { return .up }
        if avg < olderAvg * 0.95 { return .down }
        return .stable
    }

    private var hrvBaseline: Double? {
        let values = last7DaysMetrics.compactMap { $0.hrvRMSSD }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var hrvTrendData: [(date: Date, value: Double)] {
        last7DaysMetrics.compactMap { metrics in
            guard let hrv = metrics.hrvRMSSD else { return nil }
            return (metrics.date, hrv)
        }
    }

    private var rhrStatus: RHRStatus? {
        guard let rhr = todayMetrics?.restingHR else { return nil }
        guard let baseline = rhrBaseline else { return .normal }
        let deviation = Double(rhr) - baseline
        switch deviation {
        case ...(-3): return .veryLow
        case -3..<0: return .low
        case 0..<3: return .normal
        case 3..<6: return .elevated
        default: return .high
        }
    }

    private var rhrBaseline: Double? {
        let values = last7DaysMetrics.compactMap { $0.restingHR }.map { Double($0) }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var rhrTrendData: [(date: Date, value: Int)] {
        last7DaysMetrics.compactMap { metrics in
            guard let rhr = metrics.restingHR else { return nil }
            return (metrics.date, rhr)
        }
    }

    private var sleepStatus: SleepStatus? {
        guard let quality = todayMetrics?.sleepQuality else { return nil }
        switch quality {
        case 0.8...: return .excellent
        case 0.6..<0.8: return .good
        case 0.4..<0.6: return .fair
        default: return .poor
        }
    }

    private var todaySleepData: SleepData? {
        guard let metrics = todayMetrics,
              let hours = metrics.sleepHours else { return nil }

        return SleepData(
            totalSleepHours: hours,
            deepSleepMinutes: metrics.deepSleepMinutes ?? 0,
            remSleepMinutes: metrics.remSleepMinutes ?? 0,
            coreSleepMinutes: metrics.coreSleepMinutes ?? 0,
            awakeMinutes: metrics.awakeMinutes ?? 0,
            efficiency: metrics.sleepEfficiency ?? 0,
            startTime: metrics.sleepStartTime,
            endTime: metrics.sleepEndTime
        )
    }

    private var weeklyTSS: Double {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        return recentWorkouts
            .filter { $0.startDate >= weekAgo }
            .reduce(0) { $0 + $1.tss }
    }

    private var weeklyHours: Double {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        return recentWorkouts
            .filter { $0.startDate >= weekAgo }
            .reduce(0) { $0 + $1.durationSeconds } / 3600
    }

    private var weeklyWorkoutCount: Int {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        return recentWorkouts.filter { $0.startDate >= weekAgo }.count
    }

    private var weeklyByActivity: [ActivityCategory: Double] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        var result: [ActivityCategory: Double] = [:]
        for workout in recentWorkouts.filter({ $0.startDate >= weekAgo }) {
            result[workout.activityCategory, default: 0] += workout.tss
        }
        return result
    }

    // MARK: - Helper Methods

    private func generateRecommendation() -> String {
        guard let metrics = todayMetrics else {
            return "No data available yet. Complete your first workout to get personalized recommendations."
        }

        let readiness = metrics.trainingReadiness

        switch readiness {
        case .fullyReady:
            return "Your recovery metrics are excellent. Great day for a quality session or high-intensity intervals."
        case .mostlyReady:
            return "Good recovery status. Normal training is appropriate today."
        case .reducedCapacity:
            return "Signs of accumulated fatigue. Consider an easier session or active recovery."
        case .restRecommended:
            return "Recovery indicators suggest rest is needed. Take a day off or do very light activity."
        }
    }

    private func suggestWorkout() -> String? {
        guard let metrics = todayMetrics else { return nil }

        switch metrics.trainingReadiness {
        case .fullyReady:
            return "Threshold intervals or hard group ride"
        case .mostlyReady:
            return "Moderate endurance session"
        case .reducedCapacity:
            return "Easy recovery spin"
        case .restRecommended:
            return "Rest day or yoga"
        }
    }

    private func calculateReadiness() -> ReadinessResult? {
        guard let metrics = todayMetrics else { return nil }

        var hrvScore: Double? = nil
        if let hrv = metrics.hrvRMSSD, let baseline = hrvBaseline {
            hrvScore = min(100, max(0, 70 + (hrv - baseline) * 2))
        }

        var sleepScore: Double? = nil
        if let quality = metrics.sleepQuality {
            sleepScore = quality * 100
        }

        var rhrScore: Double? = nil
        if let rhr = metrics.restingHR, let baseline = rhrBaseline {
            let deviation = Double(rhr) - baseline
            rhrScore = min(100, max(0, 70 - deviation * 5))
        }

        let recoveryScore: Double? = 70  // Default

        let components = ReadinessComponents(
            hrvScore: hrvScore,
            sleepScore: sleepScore,
            rhrScore: rhrScore,
            recoveryScore: recoveryScore,
            stressScore: nil
        )

        let score = [hrvScore, sleepScore, rhrScore, recoveryScore]
            .compactMap { $0 }
            .reduce(0, +) / 4

        return ReadinessResult(
            score: score,
            readiness: TrainingReadiness(score: score),
            components: components,
            insights: []
        )
    }

    private func refreshData() async {
        if syncService == nil {
            syncService = WorkoutSyncService(healthKitService: healthKitService)
        }
        await syncService?.performIncrementalSync(modelContext: modelContext, profile: profile)
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
    }
}

// MARK: - Section Header

struct SectionHeader: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: IconSize.small))
                .foregroundStyle(Color.accentPrimary)
            Text(title.uppercased())
                .font(AppFont.labelSmall)
                .tracking(0.5)
        }
        .foregroundStyle(Color.textTertiary)
    }
}

// MARK: - Recent Workouts Card

struct RecentWorkoutsCard: View {
    let workouts: [WorkoutRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
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
                ForEach(workouts) { workout in
                    WorkoutRow(workout: workout)
                    if workout.id != workouts.last?.id {
                        Divider()
                            .background(Color.backgroundTertiary)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
}

struct WorkoutRow: View {
    let workout: WorkoutRecord

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Activity icon with colored background
            Image(systemName: workout.activityIcon)
                .font(.system(size: IconSize.medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(workout.activityCategory.themeColor)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

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

            VStack(alignment: .trailing, spacing: Spacing.xxxs) {
                Text(String(format: "%.0f", workout.tss))
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Color.textPrimary)
                Text("TSS")
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Weekly Summary Card

struct WeeklySummaryCard: View {
    let totalTSS: Double
    let totalHours: Double
    let workoutCount: Int
    let byActivity: [ActivityCategory: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("This Week".uppercased())
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)

            HStack(spacing: Spacing.lg) {
                SummaryMetric(value: String(format: "%.0f", totalTSS), label: "TSS", color: .accentPrimary)
                SummaryMetric(value: String(format: "%.1fh", totalHours), label: "Time", color: .chartFitness)
                SummaryMetric(value: "\(workoutCount)", label: "Workouts", color: .accentSecondary)
            }

            if !byActivity.isEmpty {
                Divider()
                    .background(Color.backgroundTertiary)

                HStack(spacing: Spacing.sm) {
                    ForEach(byActivity.sorted(by: { $0.value > $1.value }), id: \.key) { category, tss in
                        HStack(spacing: Spacing.xxs) {
                            Image(systemName: category.icon)
                                .font(.system(size: IconSize.small))
                            Text(String(format: "%.0f", tss))
                                .font(AppFont.labelMedium)
                        }
                        .foregroundStyle(category.themeColor)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }
}

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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Large readiness display
                    VStack(spacing: Spacing.sm) {
                        Text("\(Int(result.score))")
                            .font(AppFont.displayLarge)
                            .foregroundStyle(result.readiness.themeColor)

                        Text(result.readiness.rawValue)
                            .font(AppFont.bodyLarge)
                            .foregroundStyle(Color.textSecondary)

                        Text(result.readiness.description)
                            .font(AppFont.bodyMedium)
                            .foregroundStyle(Color.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .padding(.top, Spacing.lg)

                    // Component breakdown
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

    private var color: Color {
        switch score {
        case 80...100: return .statusExcellent
        case 60..<80: return .statusGood
        case 40..<60: return .statusModerate
        default: return .statusLow
        }
    }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: IconSize.medium))
                .foregroundStyle(color)
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
                        .fill(color)
                        .frame(width: geometry.size.width * min(score / 100, 1))
                }
            }
            .frame(width: 80, height: 6)

            Text("\(Int(score))")
                .font(AppFont.metricSmall)
                .foregroundStyle(color)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.vertical, Spacing.xs)
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
}
