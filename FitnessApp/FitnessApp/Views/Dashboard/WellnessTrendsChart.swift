import SwiftUI
import Charts

/// Chart showing 7-day trends for HRV and Resting HR
struct WellnessTrendsChart: View {
    let hrvData: [(date: Date, value: Double)]
    let rhrData: [(date: Date, value: Int)]
    @State private var selectedMetric: WellnessMetric = .hrv

    enum WellnessMetric: String, CaseIterable {
        case hrv = "HRV"
        case rhr = "Resting HR"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header with metric picker
            HStack {
                Text("Wellness Trends".uppercased())
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .tracking(0.5)

                Spacer()

                Picker("Metric", selection: $selectedMetric) {
                    ForEach(WellnessMetric.allCases, id: \.self) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }

            // Chart
            Group {
                switch selectedMetric {
                case .hrv:
                    HRVTrendChart(data: hrvData)
                case .rhr:
                    RHRTrendChart(data: rhrData)
                }
            }
            .frame(height: Layout.chartHeightStandard)
        }
        .padding(Spacing.md)
        .cardBackground()
    }
}

/// HRV trend chart
struct HRVTrendChart: View {
    let data: [(date: Date, value: Double)]
    @State private var selectedPoint: (date: Date, value: Double)?

    private var baseline: Double {
        guard !data.isEmpty else { return 0 }
        return data.map(\.value).reduce(0, +) / Double(data.count)
    }

    var body: some View {
        Chart {
            // Baseline reference area
            RectangleMark(
                xStart: .value("Start", data.first?.date ?? Date()),
                xEnd: .value("End", data.last?.date ?? Date()),
                yStart: .value("Low", baseline * 0.85),
                yEnd: .value("High", baseline * 1.15)
            )
            .foregroundStyle(Color.statusGood.opacity(0.1))

            // Baseline line
            RuleMark(y: .value("Baseline", baseline))
                .foregroundStyle(Color.textTertiary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // HRV gradient area
            ForEach(data, id: \.date) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("HRV", point.value)
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

            // HRV line
            ForEach(data, id: \.date) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("HRV", point.value)
                )
                .foregroundStyle(Color.chartFitness)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }

            // Data points
            ForEach(data, id: \.date) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("HRV", point.value)
                )
                .foregroundStyle(pointColor(point.value))
                .symbolSize(30)
            }

            // Selection indicator
            if let selected = selectedPoint {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Color.textSecondary.opacity(0.5))

                PointMark(
                    x: .value("Date", selected.date),
                    y: .value("HRV", selected.value)
                )
                .foregroundStyle(pointColor(selected.value))
                .symbolSize(100)
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
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    Text("\(value.as(Double.self) ?? 0, specifier: "%.0f")")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }
                AxisGridLine()
                    .foregroundStyle(Color.backgroundTertiary)
            }
        }
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
                                        selectedPoint = findClosest(to: date)
                                    }
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                }
                            }
                            .onEnded { _ in
                                withAnimation(AppAnimation.springSnappy) {
                                    selectedPoint = nil
                                }
                            }
                    )
            }
        }
        .chartBackground { _ in
            if let selected = selectedPoint {
                VStack(spacing: Spacing.xxxs) {
                    Text(selected.date, format: .dateTime.weekday(.abbreviated))
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                    Text(String(format: "%.0f ms", selected.value))
                        .font(AppFont.labelMedium)
                        .foregroundStyle(Color.textPrimary)
                }
                .padding(Spacing.xs)
                .background(Color.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                .offset(y: -60)
            }
        }
    }

    private func pointColor(_ value: Double) -> Color {
        let percentOfBaseline = value / baseline
        switch percentOfBaseline {
        case 1.1...: return .statusExcellent
        case 0.9..<1.1: return .statusGood
        case 0.8..<0.9: return .statusModerate
        default: return .statusLow
        }
    }

    private func findClosest(to date: Date) -> (date: Date, value: Double)? {
        data.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }
}

/// Resting HR trend chart
struct RHRTrendChart: View {
    let data: [(date: Date, value: Int)]
    @State private var selectedPoint: (date: Date, value: Int)?

    private var baseline: Double {
        guard !data.isEmpty else { return 0 }
        return Double(data.map(\.value).reduce(0, +)) / Double(data.count)
    }

    var body: some View {
        Chart {
            // Baseline reference
            RuleMark(y: .value("Baseline", baseline))
                .foregroundStyle(Color.textTertiary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

            // RHR gradient area
            ForEach(data, id: \.date) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("RHR", point.value)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.chartFatigue.opacity(0.2), Color.chartFatigue.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }

            // RHR line
            ForEach(data, id: \.date) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("RHR", point.value)
                )
                .foregroundStyle(Color.chartFatigue)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                .interpolationMethod(.catmullRom)
            }

            // Data points
            ForEach(data, id: \.date) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("RHR", point.value)
                )
                .foregroundStyle(rhrColor(point.value))
                .symbolSize(30)
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
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    Text("\(value.as(Int.self) ?? 0)")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }
                AxisGridLine()
                    .foregroundStyle(Color.backgroundTertiary)
            }
        }
        .chartYScale(domain: (Int(baseline) - 10)...(Int(baseline) + 10))
    }

    private func rhrColor(_ value: Int) -> Color {
        let deviation = Double(value) - baseline
        switch deviation {
        case ...(-3): return .statusExcellent   // Lower than normal - good
        case -3..<3: return .statusGood         // Normal
        case 3..<6: return .statusModerate      // Slightly elevated
        default: return .statusLow              // Elevated
        }
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        WellnessTrendsChart(
            hrvData: (0..<7).map { day in
                (Calendar.current.date(byAdding: .day, value: -6 + day, to: Date())!,
                 Double.random(in: 35...55))
            },
            rhrData: (0..<7).map { day in
                (Calendar.current.date(byAdding: .day, value: -6 + day, to: Date())!,
                 Int.random(in: 48...56))
            }
        )
        .padding()
    }
    .background(Color.backgroundPrimary)
}
