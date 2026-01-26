import SwiftUI
import SwiftData
import Charts

/// Unified Performance view combining PMC analytics and workout history
struct PerformanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\DailyMetrics.date, order: .forward)]) private var allMetrics: [DailyMetrics]
    @Query(sort: [SortDescriptor(\WorkoutRecord.startDate, order: .reverse)]) private var workouts: [WorkoutRecord]

    @State private var selectedDateRange: ChartDateRange = .month
    @State private var selectedSegment: PerformanceSegment = .training
    @State private var showingFullPMC = false
    @State private var selectedWorkout: WorkoutRecord?

    enum PerformanceSegment: String, CaseIterable {
        case training = "Training"
        case wellness = "Wellness"
    }

    private var pmcData: [PMCDataPoint] {
        allMetrics.map { metrics in
            PMCDataPoint(
                date: metrics.date,
                tss: metrics.totalTSS,
                ctl: metrics.ctl,
                atl: metrics.atl,
                tsb: metrics.tsb
            )
        }
    }

    private var latestMetrics: DailyMetrics? {
        allMetrics.last
    }

    private var acwr: Double? {
        guard let latest = latestMetrics, latest.ctl > 0 else { return nil }
        return latest.atl / latest.ctl
    }

    private var acwrStatus: ACWRStatus {
        PMCCalculator.analyzeACWR(acwr)
    }

    private var showACWRWarning: Bool {
        guard let ratio = acwr else { return false }
        return ratio < 0.8 || ratio > 1.3
    }

    private var recentWorkouts: [WorkoutRecord] {
        Array(workouts.prefix(3))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Conditional ACWR Warning Banner
                    if showACWRWarning {
                        acwrWarningBanner
                    }

                    // Compact PMC Chart with expand button
                    compactPMCCard

                    // Training/Wellness segment toggle
                    Picker("View", selection: $selectedSegment) {
                        ForEach(PerformanceSegment.allCases, id: \.self) { segment in
                            Text(segment.rawValue).tag(segment)
                        }
                    }
                    .pickerStyle(.segmented)

                    // Content based on selected segment
                    switch selectedSegment {
                    case .training:
                        trainingContent
                    case .wellness:
                        wellnessContent
                    }
                }
                .padding(Layout.screenPadding)
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Performance")
            .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
            .sheet(isPresented: $showingFullPMC) {
                fullPMCSheet
            }
            .sheet(item: $selectedWorkout) { workout in
                WorkoutDetailView(workout: workout)
            }
        }
    }

    // MARK: - ACWR Warning Banner

    @ViewBuilder
    private var acwrWarningBanner: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: IconSize.medium))
                .foregroundStyle(acwrStatus == .highRisk ? Color.statusLow : Color.statusModerate)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(acwrStatus == .highRisk ? "Injury Risk Warning" : "Training Load Notice")
                    .font(AppFont.labelMedium)
                    .foregroundStyle(Color.textPrimary)

                if let ratio = acwr {
                    Text("ACWR \(String(format: "%.2f", ratio)) - \(acwrStatusMessage)")
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background(
            (acwrStatus == .highRisk ? Color.statusLow : Color.statusModerate).opacity(0.15)
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke((acwrStatus == .highRisk ? Color.statusLow : Color.statusModerate).opacity(0.3), lineWidth: 1)
        )
    }

    private var acwrStatusMessage: String {
        guard let ratio = acwr else { return "Unknown" }
        if ratio < 0.8 {
            return "Training load is low - consider increasing activity"
        } else if ratio > 1.5 {
            return "High training spike - injury risk elevated"
        } else if ratio > 1.3 {
            return "Training load increasing rapidly"
        }
        return "Within optimal range"
    }

    // MARK: - Compact PMC Card

    @ViewBuilder
    private var compactPMCCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header with expand button
            HStack {
                Text("PMC Trend".uppercased())
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)

                Spacer()

                // Time range selector
                HStack(spacing: Spacing.xxs) {
                    ForEach([ChartDateRange.week, .month, .quarter], id: \.self) { range in
                        Button {
                            withAnimation(AppAnimation.springSnappy) {
                                selectedDateRange = range
                            }
                        } label: {
                            Text(range.shortLabel)
                                .font(AppFont.captionSmall)
                                .padding(.horizontal, Spacing.xs)
                                .padding(.vertical, Spacing.xxs)
                                .background(selectedDateRange == range ? Color.accentPrimary : Color.backgroundTertiary)
                                .foregroundStyle(selectedDateRange == range ? .white : Color.textSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    showingFullPMC = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: IconSize.small))
                        .foregroundStyle(Color.textSecondary)
                        .padding(Spacing.xs)
                        .background(Color.backgroundTertiary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            // Compact chart
            CompactPMCChart(data: pmcData, selectedDateRange: selectedDateRange)
                .frame(height: 120)

            // Inline legend with current values
            if let latest = latestMetrics {
                HStack(spacing: Spacing.md) {
                    MetricLegendItem(
                        color: .chartFitness,
                        label: "Fitness",
                        value: String(format: "%.0f", latest.ctl)
                    )
                    MetricLegendItem(
                        color: .chartFatigue,
                        label: "Fatigue",
                        value: String(format: "%.0f", latest.atl)
                    )
                    MetricLegendItem(
                        color: Color.forTSB(latest.tsb),
                        label: "Form",
                        value: String(format: "%+.0f", latest.tsb)
                    )
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    // MARK: - Training Content

    @ViewBuilder
    private var trainingContent: some View {
        VStack(spacing: Spacing.lg) {
            // Recent Workouts Card
            workoutsCard
        }
    }

    // MARK: - Workouts Card

    @ViewBuilder
    private var workoutsCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header
            HStack {
                Text("Workouts".uppercased())
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)

                Spacer()

                NavigationLink(destination: WorkoutsListView()) {
                    HStack(spacing: Spacing.xxs) {
                        Text("See All")
                            .font(AppFont.labelSmall)
                        Image(systemName: "chevron.right")
                            .font(.system(size: IconSize.tiny))
                    }
                    .foregroundStyle(Color.accentPrimary)
                }
            }

            if recentWorkouts.isEmpty {
                // Empty state
                VStack(spacing: Spacing.sm) {
                    Image(systemName: "figure.run")
                        .font(.system(size: IconSize.extraLarge))
                        .foregroundStyle(Color.textTertiary)
                    Text("No workouts yet")
                        .font(AppFont.bodyMedium)
                        .foregroundStyle(Color.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Spacing.xl)
            } else {
                // Workout list
                VStack(spacing: Spacing.xs) {
                    ForEach(recentWorkouts) { workout in
                        CompactWorkoutRow(workout: workout)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedWorkout = workout
                            }

                        if workout.id != recentWorkouts.last?.id {
                            Divider()
                                .background(Color.backgroundTertiary)
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    // MARK: - Wellness Content

    @ViewBuilder
    private var wellnessContent: some View {
        VStack(spacing: Spacing.lg) {
            // HRV Trend Card
            hrvTrendCard

            // Sleep Trend Card
            sleepTrendCard

            // Resting HR Card
            restingHRCard
        }
    }

    @ViewBuilder
    private var hrvTrendCard: some View {
        let hrvData = allMetrics.suffix(30).compactMap { m -> (Date, Double)? in
            guard let hrv = m.hrvRMSSD else { return nil }
            return (m.date, hrv)
        }

        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("HRV Trend".uppercased())
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)

                Spacer()

                if let latest = hrvData.last {
                    Text("\(Int(latest.1)) ms")
                        .font(AppFont.labelMedium)
                        .foregroundStyle(Color.accentPrimary)
                }
            }

            if hrvData.isEmpty {
                emptyMetricState(icon: "waveform.path.ecg", message: "No HRV data")
            } else {
                CompactTrendChart(
                    data: hrvData,
                    color: .chartFitness,
                    showBaseline: true
                )
                .frame(height: 80)

                // 7-day average
                let sevenDayAvg = hrvData.suffix(7).map(\.1).reduce(0, +) / Double(max(1, min(7, hrvData.count)))
                HStack {
                    Text("7-day avg:")
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.textTertiary)
                    Text("\(Int(sevenDayAvg)) ms")
                        .font(AppFont.labelSmall)
                        .foregroundStyle(Color.textSecondary)

                    if let latest = hrvData.last {
                        Spacer()
                        Text("Today:")
                            .font(AppFont.captionLarge)
                            .foregroundStyle(Color.textTertiary)
                        Text("\(Int(latest.1)) ms")
                            .font(AppFont.labelSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    @ViewBuilder
    private var sleepTrendCard: some View {
        let sleepData = allMetrics.suffix(14).compactMap { m -> (Date, Double)? in
            guard let hours = m.sleepHours else { return nil }
            return (m.date, hours)
        }

        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Sleep Quality".uppercased())
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)

                Spacer()

                if let latest = sleepData.last {
                    Text(formatSleepDuration(latest.1))
                        .font(AppFont.labelMedium)
                        .foregroundStyle(Color.accentPrimary)
                }
            }

            if sleepData.isEmpty {
                emptyMetricState(icon: "moon.fill", message: "No sleep data")
            } else {
                SleepBarChart(data: sleepData)
                    .frame(height: 80)

                // 7-day average
                let sevenDayAvg = sleepData.suffix(7).map(\.1).reduce(0, +) / Double(max(1, min(7, sleepData.count)))
                HStack {
                    Text("7-day avg:")
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.textTertiary)
                    Text(formatSleepDuration(sevenDayAvg))
                        .font(AppFont.labelSmall)
                        .foregroundStyle(Color.textSecondary)

                    if let latest = sleepData.last {
                        Spacer()
                        Text("Last:")
                            .font(AppFont.captionLarge)
                            .foregroundStyle(Color.textTertiary)
                        Text(formatSleepDuration(latest.1))
                            .font(AppFont.labelSmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    @ViewBuilder
    private var restingHRCard: some View {
        let rhrData = allMetrics.suffix(7).compactMap { m -> (Date, Int)? in
            guard let rhr = m.restingHR else { return nil }
            return (m.date, rhr)
        }

        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Resting Heart Rate".uppercased())
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)

                Spacer()

                if let latest = rhrData.last {
                    Text("\(latest.1) bpm")
                        .font(AppFont.labelMedium)
                        .foregroundStyle(Color.accentPrimary)
                }
            }

            if rhrData.isEmpty {
                emptyMetricState(icon: "heart.fill", message: "No resting HR data")
            } else {
                let avgRHR = rhrData.map(\.1).reduce(0, +) / max(1, rhrData.count)

                HStack(spacing: Spacing.lg) {
                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("Current")
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.textTertiary)
                        if let latest = rhrData.last {
                            HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                                Text("\(latest.1)")
                                    .font(AppFont.metricMedium)
                                    .foregroundStyle(Color.textPrimary)
                                Text("bpm")
                                    .font(AppFont.captionLarge)
                                    .foregroundStyle(Color.textTertiary)
                            }
                        }
                    }

                    Divider()
                        .frame(height: 40)

                    VStack(alignment: .leading, spacing: Spacing.xxs) {
                        Text("7-day avg")
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.textTertiary)
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
                            Text("\(avgRHR)")
                                .font(AppFont.metricMedium)
                                .foregroundStyle(Color.textPrimary)
                            Text("bpm")
                                .font(AppFont.captionLarge)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }

                    if let latest = rhrData.last {
                        Spacer()
                        let diff = latest.1 - avgRHR
                        VStack(alignment: .trailing, spacing: Spacing.xxs) {
                            Text("vs avg")
                                .font(AppFont.captionSmall)
                                .foregroundStyle(Color.textTertiary)
                            Text("\(diff >= 0 ? "+" : "")\(diff)")
                                .font(AppFont.labelMedium)
                                .foregroundStyle(diff <= 0 ? Color.statusOptimal : (diff <= 3 ? Color.statusModerate : Color.statusLow))
                        }
                    }
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    @ViewBuilder
    private func emptyMetricState(icon: String, message: String) -> some View {
        VStack(spacing: Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: IconSize.large))
                .foregroundStyle(Color.textTertiary)
            Text(message)
                .font(AppFont.captionLarge)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.lg)
    }

    private func formatSleepDuration(_ hours: Double) -> String {
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    // MARK: - Full PMC Sheet

    @ViewBuilder
    private var fullPMCSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Time range picker
                Picker("Range", selection: $selectedDateRange) {
                    ForEach(ChartDateRange.allCases, id: \.self) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .padding(Spacing.md)

                // Full PMC Chart
                PMCChart(data: pmcData, selectedDateRange: $selectedDateRange)
                    .padding(.horizontal, Spacing.md)

                Spacer()

                // Current values summary
                if let latest = latestMetrics {
                    VStack(spacing: Spacing.sm) {
                        HStack(spacing: Spacing.xl) {
                            VStack(spacing: Spacing.xxs) {
                                Text("Fitness (CTL)")
                                    .font(AppFont.captionLarge)
                                    .foregroundStyle(Color.textTertiary)
                                Text(String(format: "%.0f", latest.ctl))
                                    .font(AppFont.metricLarge)
                                    .foregroundStyle(Color.chartFitness)
                            }

                            VStack(spacing: Spacing.xxs) {
                                Text("Fatigue (ATL)")
                                    .font(AppFont.captionLarge)
                                    .foregroundStyle(Color.textTertiary)
                                Text(String(format: "%.0f", latest.atl))
                                    .font(AppFont.metricLarge)
                                    .foregroundStyle(Color.chartFatigue)
                            }

                            VStack(spacing: Spacing.xxs) {
                                Text("Form (TSB)")
                                    .font(AppFont.captionLarge)
                                    .foregroundStyle(Color.textTertiary)
                                Text(String(format: "%+.0f", latest.tsb))
                                    .font(AppFont.metricLarge)
                                    .foregroundStyle(Color.forTSB(latest.tsb))
                            }
                        }

                        Text(latest.formStatus + " (\(PMCCalculator.trainingRecommendation(tsb: latest.tsb).status.rawValue))")
                            .font(AppFont.bodyMedium)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .padding(Spacing.lg)
                    .frame(maxWidth: .infinity)
                    .background(Color.backgroundSecondary)
                }
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("PMC Chart")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showingFullPMC = false
                    }
                }
            }
            .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
    }
}

// MARK: - Supporting Views

/// Compact PMC chart for inline display
struct CompactPMCChart: View {
    let data: [PMCDataPoint]
    let selectedDateRange: ChartDateRange

    private var filteredData: [PMCDataPoint] {
        guard let days = selectedDateRange.days else { return data }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return data.filter { $0.date >= cutoff }
    }

    private var yAxisDomain: ClosedRange<Double> {
        guard !filteredData.isEmpty else { return 0...100 }
        let allValues = filteredData.flatMap { [$0.ctl, $0.atl] }
        guard let minVal = allValues.min(), let maxVal = allValues.max() else { return 0...100 }
        let padding = (maxVal - minVal) * 0.15
        return (minVal - padding)...(maxVal + padding)
    }

    var body: some View {
        Chart {
            // CTL (Fitness) area
            ForEach(filteredData) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Base", yAxisDomain.lowerBound),
                    yEnd: .value("CTL", point.ctl)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.chartFitness.opacity(0.2), Color.chartFitness.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            // CTL line
            ForEach(filteredData) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("CTL", point.ctl),
                    series: .value("Metric", "Fitness")
                )
                .foregroundStyle(Color.chartFitness)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }

            // ATL (Fatigue) area
            ForEach(filteredData) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    yStart: .value("Base", yAxisDomain.lowerBound),
                    yEnd: .value("ATL", point.atl)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.chartFatigue.opacity(0.15), Color.chartFatigue.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            // ATL line
            ForEach(filteredData) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("ATL", point.atl),
                    series: .value("Metric", "Fatigue")
                )
                .foregroundStyle(Color.chartFatigue)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: yAxisDomain)
    }
}

/// Metric legend item with colored dot
struct MetricLegendItem: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
                .font(AppFont.captionSmall)
                .foregroundStyle(Color.textTertiary)
            Text(value)
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textPrimary)
        }
    }
}

/// Compact workout row for performance view
struct CompactWorkoutRow: View {
    let workout: WorkoutRecord

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Activity icon
            Image(systemName: workout.activityIcon)
                .font(.system(size: IconSize.medium))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(workout.activityCategory.themeColor)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

            // Info
            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(workout.title ?? workout.activityType)
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Spacing.xs) {
                    Text(workout.durationFormatted)
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                    if let distance = workout.distanceFormatted {
                        Text("•")
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.textTertiary)
                        Text(distance)
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }

            Spacer()

            // TSS and date
            VStack(alignment: .trailing, spacing: Spacing.xxxs) {
                HStack(spacing: Spacing.xxs) {
                    Text(String(format: "%.0f", workout.tss))
                        .font(AppFont.labelMedium)
                        .foregroundStyle(Color.textPrimary)
                    Text("TSS")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }

                Text(workout.relativeDateString)
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xxs)
    }
}

/// Compact trend chart for wellness metrics
struct CompactTrendChart: View {
    let data: [(Date, Double)]
    let color: Color
    let showBaseline: Bool

    private var baseline: Double {
        guard !data.isEmpty else { return 0 }
        return data.map(\.1).reduce(0, +) / Double(data.count)
    }

    var body: some View {
        Chart {
            if showBaseline {
                RuleMark(y: .value("Baseline", baseline))
                    .foregroundStyle(Color.textTertiary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }

            ForEach(data, id: \.0) { point in
                AreaMark(
                    x: .value("Date", point.0),
                    y: .value("Value", point.1)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [color.opacity(0.2), color.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            ForEach(data, id: \.0) { point in
                LineMark(
                    x: .value("Date", point.0),
                    y: .value("Value", point.1)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }
}

/// Sleep bar chart showing nightly sleep
struct SleepBarChart: View {
    let data: [(Date, Double)]

    var body: some View {
        Chart {
            // Target zone (7-9 hours)
            RectangleMark(
                xStart: .value("Start", data.first?.0 ?? Date()),
                xEnd: .value("End", data.last?.0 ?? Date()),
                yStart: .value("Low", 7),
                yEnd: .value("High", 9)
            )
            .foregroundStyle(Color.statusOptimal.opacity(0.1))

            ForEach(data, id: \.0) { point in
                BarMark(
                    x: .value("Date", point.0, unit: .day),
                    y: .value("Hours", point.1)
                )
                .foregroundStyle(sleepColor(point.1))
                .cornerRadius(3)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...12)
    }

    private func sleepColor(_ hours: Double) -> Color {
        switch hours {
        case 7...9: return .statusOptimal
        case 6..<7, 9..<10: return .accentSecondary
        default: return .statusModerate
        }
    }
}

// MARK: - Date Range Extension

extension ChartDateRange {
    var shortLabel: String {
        switch self {
        case .week: return "7D"
        case .month: return "30D"
        case .quarter: return "90D"
        case .year: return "1Y"
        case .all: return "All"
        }
    }
}

// MARK: - Workout Record Extension

extension WorkoutRecord {
    var relativeDateString: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(startDate) {
            return "Today"
        } else if calendar.isDateInYesterday(startDate) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: startDate)
        }
    }
}

// MARK: - Calendar Helper

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}

// MARK: - Preview

#Preview {
    PerformanceView()
        .modelContainer(for: [DailyMetrics.self, WorkoutRecord.self], inMemory: true)
}
