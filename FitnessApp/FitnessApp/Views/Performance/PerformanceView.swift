import SwiftUI
import SwiftData
import Charts

/// Performance view showing PMC chart and detailed training metrics
struct PerformanceView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\DailyMetrics.date, order: .forward)]) private var allMetrics: [DailyMetrics]
    @Query(sort: [SortDescriptor(\WorkoutRecord.startDate, order: .reverse)]) private var workouts: [WorkoutRecord]

    @State private var selectedDateRange: ChartDateRange = .month
    @State private var selectedTab: PerformanceTab = .pmc
    @State private var selectedDate: Date?

    enum PerformanceTab: String, CaseIterable {
        case pmc = "PMC"
        case wellness = "Wellness"
        case load = "Training Load"
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                Picker("View", selection: $selectedTab) {
                    ForEach(PerformanceTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(Spacing.md)

                // Content
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        switch selectedTab {
                        case .pmc:
                            pmcContent
                        case .wellness:
                            wellnessContent
                        case .load:
                            loadContent
                        }
                    }
                    .padding(Layout.screenPadding)
                }
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Performance")
            .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - PMC Content

    @ViewBuilder
    private var pmcContent: some View {
        VStack(spacing: 16) {
            // Main PMC Chart
            PMCChart(data: pmcData, selectedDateRange: $selectedDateRange)
                .frame(height: 350)

            // Current metrics summary
            currentMetricsSummary

            // Training zones
            trainingZoneSummary
        }
    }

    @ViewBuilder
    private var currentMetricsSummary: some View {
        if let latest = allMetrics.last {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("Current Status".uppercased())
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)

                HStack(spacing: Spacing.md) {
                    MetricBox(
                        title: "Fitness (CTL)",
                        value: String(format: "%.0f", latest.ctl),
                        subtitle: latest.fitnessStatus,
                        color: .chartFitness
                    )

                    MetricBox(
                        title: "Fatigue (ATL)",
                        value: String(format: "%.0f", latest.atl),
                        subtitle: acwrStatus(ctl: latest.ctl, atl: latest.atl),
                        color: .chartFatigue
                    )

                    MetricBox(
                        title: "Form (TSB)",
                        value: String(format: "%+.0f", latest.tsb),
                        subtitle: latest.formStatus,
                        color: formColor(latest.tsb)
                    )
                }

                // ACWR indicator
                ACWRIndicator(ctl: latest.ctl, atl: latest.atl)
            }
            .padding(Spacing.md)
            .cardBackground()
        }
    }

    @ViewBuilder
    private var trainingZoneSummary: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Optimal Training Zone".uppercased())
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)

            Text("Based on your current form of \(String(format: "%+.0f", allMetrics.last?.tsb ?? 0)) TSB:")
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)

            let recommendation = PMCCalculator.trainingRecommendation(tsb: allMetrics.last?.tsb ?? 0)

            HStack(spacing: Spacing.xs) {
                Circle()
                    .fill(statusColor(recommendation.status))
                    .frame(width: 12, height: 12)

                Text(recommendation.recommendation)
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(Color.textPrimary)
            }

            HStack(spacing: Spacing.xs) {
                Text("Suggested TSS:")
                    .font(AppFont.captionLarge)
                    .foregroundStyle(Color.textTertiary)
                Text("\(Int(recommendation.suggestedTSS.lowerBound)) - \(Int(recommendation.suggestedTSS.upperBound))")
                    .font(AppFont.labelMedium)
                    .foregroundStyle(Color.accentPrimary)
            }
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    // MARK: - Wellness Content

    @ViewBuilder
    private var wellnessContent: some View {
        VStack(spacing: 16) {
            // HRV Trend Chart
            WellnessMetricChart(
                title: "HRV Trend",
                data: allMetrics.compactMap { m in
                    guard let hrv = m.hrvRMSSD else { return nil }
                    return (m.date, hrv)
                },
                dateRange: selectedDateRange,
                unit: "ms",
                color: .blue,
                higherIsBetter: true
            )

            // Resting HR Trend
            WellnessMetricChart(
                title: "Resting Heart Rate",
                data: allMetrics.compactMap { m in
                    guard let rhr = m.restingHR else { return nil }
                    return (m.date, Double(rhr))
                },
                dateRange: selectedDateRange,
                unit: "bpm",
                color: .red,
                higherIsBetter: false
            )

            // Sleep Trend
            SleepTrendChart(
                data: allMetrics.compactMap { m in
                    guard let hours = m.sleepHours else { return nil }
                    return (m.date, hours, m.sleepQuality ?? 0.5)
                },
                dateRange: selectedDateRange
            )
        }
    }

    // MARK: - Load Content

    @ViewBuilder
    private var loadContent: some View {
        VStack(spacing: 16) {
            // Weekly TSS by activity
            WeeklyLoadChart(workouts: workouts, dateRange: selectedDateRange)

            // Training distribution
            TrainingDistributionCard(workouts: workouts, dateRange: selectedDateRange)

            // Monotony and strain
            MonotonyStrainCard(metrics: allMetrics)
        }
    }

    // MARK: - Helper Methods

    private func acwrStatus(ctl: Double, atl: Double) -> String {
        guard ctl > 0 else { return "N/A" }
        let acwr = atl / ctl
        switch acwr {
        case 0.8...1.3: return "Optimal"
        case 0.5..<0.8: return "Low"
        case 1.3..<1.5: return "Caution"
        default: return "High Risk"
        }
    }

    private func formColor(_ tsb: Double) -> Color {
        Color.forTSB(tsb)
    }

    private func statusColor(_ status: TSBStatus) -> Color {
        switch status {
        case .veryFresh: return .statusExcellent
        case .fresh: return .statusGood
        case .neutral: return .chartFitness
        case .tired: return .statusModerate
        case .veryTired: return .statusLow
        }
    }
}

// MARK: - Supporting Views

struct MetricBox: View {
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Text(title)
                .font(AppFont.captionSmall)
                .foregroundStyle(Color.textTertiary)

            Text(value)
                .font(AppFont.metricMedium)
                .foregroundStyle(color)

            Text(subtitle)
                .font(AppFont.captionSmall)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct ACWRIndicator: View {
    let ctl: Double
    let atl: Double

    private var acwr: Double? {
        guard ctl > 0 else { return nil }
        return atl / ctl
    }

    private var status: ACWRStatus {
        PMCCalculator.analyzeACWR(acwr)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Acute:Chronic Workload Ratio")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                // Gauge
                ZStack {
                    // Background track
                    Capsule()
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    // Optimal zone
                    GeometryReader { geo in
                        Capsule()
                            .fill(Color.green.opacity(0.3))
                            .frame(width: geo.size.width * 0.25)
                            .offset(x: geo.size.width * 0.35)
                    }
                    .frame(height: 8)

                    // Current position
                    GeometryReader { geo in
                        if let ratio = acwr {
                            let position = max(0, min(1, ratio / 2)) // Scale 0-2 to 0-1
                            Circle()
                                .fill(statusColor)
                                .frame(width: 12, height: 12)
                                .offset(x: geo.size.width * position - 6)
                        }
                    }
                    .frame(height: 12)
                }

                if let ratio = acwr {
                    Text(String(format: "%.2f", ratio))
                        .font(.headline)
                        .foregroundStyle(statusColor)
                }
            }

            // Labels
            HStack {
                Text("0")
                Spacer()
                Text("0.8-1.3 Optimal")
                Spacer()
                Text("2.0+")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(statusColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var statusColor: Color {
        switch status {
        case .optimal: return .green
        case .undertraining: return .blue
        case .caution: return .orange
        case .highRisk: return .red
        case .veryLow, .unknown: return .gray
        }
    }
}

struct WellnessMetricChart: View {
    let title: String
    let data: [(Date, Double)]
    let dateRange: ChartDateRange
    let unit: String
    let color: Color
    let higherIsBetter: Bool

    private var filteredData: [(Date, Double)] {
        guard let days = dateRange.days else { return data }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return data.filter { $0.0 >= cutoff }
    }

    private var baseline: Double {
        guard !filteredData.isEmpty else { return 0 }
        return filteredData.map(\.1).reduce(0, +) / Double(filteredData.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)

                Spacer()

                if let latest = filteredData.last {
                    Text("\(Int(latest.1)) \(unit)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(color)
                }
            }

            Chart {
                // Baseline
                RuleMark(y: .value("Baseline", baseline))
                    .foregroundStyle(.gray.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                // Data line
                ForEach(filteredData, id: \.0) { point in
                    LineMark(
                        x: .value("Date", point.0),
                        y: .value("Value", point.1)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }

                // Points
                ForEach(filteredData, id: \.0) { point in
                    PointMark(
                        x: .value("Date", point.0),
                        y: .value("Value", point.1)
                    )
                    .foregroundStyle(pointColor(point.1))
                    .symbolSize(20)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisValueLabel(format: .dateTime.day())
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 150)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func pointColor(_ value: Double) -> Color {
        let deviation = (value - baseline) / baseline
        if higherIsBetter {
            if deviation > 0.1 { return .green }
            if deviation < -0.1 { return .red }
        } else {
            if deviation > 0.1 { return .red }
            if deviation < -0.1 { return .green }
        }
        return color
    }
}

struct SleepTrendChart: View {
    let data: [(date: Date, hours: Double, quality: Double)]
    let dateRange: ChartDateRange

    private var filteredData: [(date: Date, hours: Double, quality: Double)] {
        guard let days = dateRange.days else { return data }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return data.filter { $0.date >= cutoff }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sleep")
                .font(.headline)

            Chart {
                // Target zone
                RectangleMark(
                    xStart: .value("Start", filteredData.first?.date ?? Date()),
                    xEnd: .value("End", filteredData.last?.date ?? Date()),
                    yStart: .value("Low", 7),
                    yEnd: .value("High", 9)
                )
                .foregroundStyle(.green.opacity(0.1))

                ForEach(filteredData, id: \.date) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: .day),
                        y: .value("Hours", point.hours)
                    )
                    .foregroundStyle(sleepColor(point.hours, quality: point.quality))
                    .cornerRadius(4)
                }
            }
            .chartYScale(domain: 0...12)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(.caption2)
                }
            }
            .frame(height: 150)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func sleepColor(_ hours: Double, quality: Double) -> Color {
        if hours >= 7 && quality >= 0.7 {
            return .green
        } else if hours >= 6 && quality >= 0.5 {
            return .blue
        } else if hours >= 5 {
            return .orange
        }
        return .red
    }
}

struct WeeklyLoadChart: View {
    let workouts: [WorkoutRecord]
    let dateRange: ChartDateRange

    private var weeklyData: [(week: Date, tss: Double, category: ActivityCategory)] {
        let calendar = Calendar.current
        var result: [(Date, Double, ActivityCategory)] = []

        guard let days = dateRange.days else { return result }
        let cutoff = calendar.date(byAdding: .day, value: -days, to: Date())!

        let filtered = workouts.filter { $0.startDate >= cutoff }
        let grouped = Dictionary(grouping: filtered) { workout in
            calendar.startOfWeek(for: workout.startDate)
        }

        for (week, weekWorkouts) in grouped {
            for category in ActivityCategory.allCases {
                let categoryTSS = weekWorkouts
                    .filter { $0.activityCategory == category }
                    .reduce(0) { $0 + $1.tss }
                if categoryTSS > 0 {
                    result.append((week, categoryTSS, category))
                }
            }
        }

        return result.sorted { $0.0 < $1.0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Training Load")
                .font(.headline)

            Chart {
                ForEach(weeklyData, id: \.week) { item in
                    BarMark(
                        x: .value("Week", item.week, unit: .weekOfYear),
                        y: .value("TSS", item.tss)
                    )
                    .foregroundStyle(by: .value("Activity", item.category.rawValue))
                }
            }
            .chartForegroundStyleScale([
                "Run": Color.orange,
                "Bike": Color.blue,
                "Swim": Color.cyan,
                "Strength": Color.purple,
                "Other": Color.gray
            ])
            .frame(height: 200)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct TrainingDistributionCard: View {
    let workouts: [WorkoutRecord]
    let dateRange: ChartDateRange

    private var distribution: [(category: ActivityCategory, percentage: Double, tss: Double)] {
        guard let days = dateRange.days else { return [] }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let filtered = workouts.filter { $0.startDate >= cutoff }

        let totalTSS = filtered.reduce(0) { $0 + $1.tss }
        guard totalTSS > 0 else { return [] }

        return ActivityCategory.allCases.compactMap { category in
            let categoryTSS = filtered.filter { $0.activityCategory == category }.reduce(0) { $0 + $1.tss }
            guard categoryTSS > 0 else { return nil }
            return (category, categoryTSS / totalTSS, categoryTSS)
        }.sorted { $0.percentage > $1.percentage }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Distribution")
                .font(.headline)

            ForEach(distribution, id: \.category) { item in
                HStack {
                    Image(systemName: item.category.icon)
                        .frame(width: 24)

                    Text(item.category.rawValue)
                        .font(.subheadline)

                    Spacer()

                    Text(String(format: "%.0f%%", item.percentage * 100))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text(String(format: "%.0f TSS", item.tss))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.2))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(categoryColor(item.category))
                            .frame(width: geo.size.width * item.percentage)
                    }
                }
                .frame(height: 4)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func categoryColor(_ category: ActivityCategory) -> Color {
        switch category {
        case .run: return .orange
        case .bike: return .blue
        case .swim: return .cyan
        case .strength: return .purple
        case .other: return .gray
        }
    }
}

struct MonotonyStrainCard: View {
    let metrics: [DailyMetrics]

    private var weeklyTSS: [Double] {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        return metrics
            .filter { $0.date >= weekAgo }
            .sorted { $0.date < $1.date }
            .map { $0.totalTSS }
    }

    private var monotony: Double? {
        PMCCalculator.calculateMonotony(weeklyTSS: weeklyTSS)
    }

    private var strain: Double? {
        PMCCalculator.calculateStrain(weeklyTSS: weeklyTSS)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Stress")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("Monotony")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let m = monotony {
                        Text(String(format: "%.1f", m))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(monotonyColor(m))
                    } else {
                        Text("--")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }

                    Text(monotonyStatus)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(spacing: 4) {
                    Text("Strain")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let s = strain {
                        Text(String(format: "%.0f", s))
                            .font(.title2)
                            .fontWeight(.bold)
                    } else {
                        Text("--")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }

                    Text("Weekly load × monotony")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            if let m = monotony, m > 2.0 {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("High monotony with high strain increases injury risk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func monotonyColor(_ value: Double) -> Color {
        switch value {
        case ...1.5: return .green
        case 1.5..<2.0: return .orange
        default: return .red
        }
    }

    private var monotonyStatus: String {
        guard let m = monotony else { return "Insufficient data" }
        switch m {
        case ...1.5: return "Good variety"
        case 1.5..<2.0: return "Moderate"
        default: return "High - add variety"
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
