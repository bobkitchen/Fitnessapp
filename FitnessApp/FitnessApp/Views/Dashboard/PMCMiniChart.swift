import SwiftUI
import Charts

/// Mini PMC chart for dashboard showing 7-day trend
struct PMCMiniChart: View {
    let data: [PMCDataPoint]
    let selectedDate: Date?
    let onSelectDate: ((Date) -> Void)?

    @State private var selectedDataPoint: PMCDataPoint?
    @State private var hasAppeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            // Header
            HStack {
                Text("7-Day Trend".uppercased())
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)

                Spacer()

                if let selected = selectedDataPoint {
                    VStack(alignment: .trailing, spacing: Spacing.xxxs) {
                        Text(selected.date, style: .date)
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.textTertiary)
                        HStack(spacing: Spacing.xxs) {
                            Text("TSB")
                                .font(AppFont.captionSmall)
                                .foregroundStyle(Color.textTertiary)
                            Text(String(format: "%+.0f", selected.tsb))
                                .font(AppFont.labelMedium)
                                .foregroundStyle(Color.forTSB(selected.tsb))
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }

            // Chart
            Chart {
                // Optimal TSB zone shading (-10 to +15)
                RectangleMark(
                    xStart: .value("Start", data.first?.date ?? Date()),
                    xEnd: .value("End", data.last?.date ?? Date()),
                    yStart: .value("Low", -10),
                    yEnd: .value("High", 15)
                )
                .foregroundStyle(Color.statusGood.opacity(0.05))

                // CTL gradient area
                ForEach(data) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Base", yAxisMin),
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
                ForEach(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("CTL", point.ctl),
                        series: .value("Metric", "Fitness")
                    )
                    .foregroundStyle(Color.chartFitness)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }

                // ATL gradient area
                ForEach(data) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Base", yAxisMin),
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
                ForEach(data) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("ATL", point.atl),
                        series: .value("Metric", "Fatigue")
                    )
                    .foregroundStyle(Color.chartFatigue)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.catmullRom)
                }

                // Zero line for TSB reference
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(Color.textTertiary.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                // Selection indicator
                if let selected = selectedDataPoint {
                    RuleMark(x: .value("Selected", selected.date))
                        .foregroundStyle(Color.textSecondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))

                    PointMark(x: .value("Date", selected.date), y: .value("CTL", selected.ctl))
                        .foregroundStyle(Color.chartFitness)
                        .symbolSize(60)

                    PointMark(x: .value("Date", selected.date), y: .value("ATL", selected.atl))
                        .foregroundStyle(Color.chartFatigue)
                        .symbolSize(60)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .frame(height: Layout.chartHeightCompact)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x
                                    if let date: Date = proxy.value(atX: x) {
                                        withAnimation(AppAnimation.springSnappy) {
                                            selectedDataPoint = findClosestDataPoint(to: date)
                                        }
                                        // Haptic feedback
                                        let generator = UIImpactFeedbackGenerator(style: .light)
                                        generator.impactOccurred()
                                    }
                                }
                                .onEnded { _ in
                                    if let point = selectedDataPoint {
                                        onSelectDate?(point.date)
                                    }
                                }
                        )
                }
            }
            .opacity(hasAppeared ? 1 : 0)

            // Legend
            HStack(spacing: Spacing.md) {
                LegendItem(color: .chartFitness, label: "Fitness")
                LegendItem(color: .chartFatigue, label: "Fatigue")
                LegendItem(color: .statusGood, label: "Form Zone")
            }
        }
        .padding(Spacing.md)
        .cardBackground()
        .onAppear {
            withAnimation(AppAnimation.springGentle.delay(0.3)) {
                hasAppeared = true
            }
        }
    }

    private var yAxisMin: Double {
        let allValues = data.flatMap { [$0.ctl, $0.atl, $0.tsb] }
        return (allValues.min() ?? 0) - 10
    }

    private func findClosestDataPoint(to date: Date) -> PMCDataPoint? {
        data.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }
}

/// Legend item for chart
struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: Spacing.xxs) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(AppFont.captionSmall)
                .foregroundStyle(Color.textTertiary)
        }
    }
}

/// Weekly TSS bar chart
struct WeeklyTSSChart: View {
    let data: [(date: Date, tss: Double, category: ActivityCategory)]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Weekly Load".uppercased())
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)

            Chart {
                ForEach(data, id: \.date) { item in
                    BarMark(
                        x: .value("Day", item.date, unit: .day),
                        y: .value("TSS", item.tss)
                    )
                    .foregroundStyle(item.category.themeColor)
                    .cornerRadius(CornerRadius.small / 2)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                    AxisGridLine()
                        .foregroundStyle(Color.backgroundTertiary)
                }
            }
            .frame(height: Layout.chartHeightStandard)
        }
        .padding(Spacing.md)
        .cardBackground()
    }
}

// MARK: - Preview

#Preview {
    let sampleData: [PMCDataPoint] = (0..<7).map { day in
        let date = Calendar.current.date(byAdding: .day, value: -6 + day, to: Date())!
        return PMCDataPoint(
            date: date,
            tss: Double.random(in: 50...120),
            ctl: 70 + Double(day) * 0.5,
            atl: 80 + Double.random(in: -5...5),
            tsb: -10 + Double(day) * 2
        )
    }

    ScrollView {
        VStack(spacing: Spacing.lg) {
            PMCMiniChart(
                data: sampleData,
                selectedDate: nil,
                onSelectDate: nil
            )

            WeeklyTSSChart(data: [
                (Calendar.current.date(byAdding: .day, value: -6, to: Date())!, 80, .bike),
                (Calendar.current.date(byAdding: .day, value: -5, to: Date())!, 45, .run),
                (Calendar.current.date(byAdding: .day, value: -4, to: Date())!, 0, .other),
                (Calendar.current.date(byAdding: .day, value: -3, to: Date())!, 95, .bike),
                (Calendar.current.date(byAdding: .day, value: -2, to: Date())!, 60, .run),
                (Calendar.current.date(byAdding: .day, value: -1, to: Date())!, 30, .swim),
                (Date(), 0, .other)
            ])
        }
        .padding()
    }
    .background(Color.backgroundPrimary)
}
