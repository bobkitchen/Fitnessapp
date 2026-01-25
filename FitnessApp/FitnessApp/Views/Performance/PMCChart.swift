import SwiftUI
import Charts

/// Full-screen PMC chart with interactive features
struct PMCChart: View {
    let data: [PMCDataPoint]
    @Binding var selectedDateRange: ChartDateRange

    @State private var selectedDataPoint: PMCDataPoint?
    @State private var showingCTL = true
    @State private var showingATL = true
    @State private var showingTSB = true

    private var filteredData: [PMCDataPoint] {
        guard let days = selectedDateRange.days else { return data }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return data.filter { $0.date >= cutoff }
    }

    private var yAxisDomain: ClosedRange<Double> {
        guard !filteredData.isEmpty else { return 0...100 }

        var allValues: [Double] = []
        if showingCTL { allValues.append(contentsOf: filteredData.map(\.ctl)) }
        if showingATL { allValues.append(contentsOf: filteredData.map(\.atl)) }
        if showingTSB { allValues.append(contentsOf: filteredData.map(\.tsb)) }

        guard let minVal = allValues.min(), let maxVal = allValues.max() else {
            return 0...100
        }

        let padding = (maxVal - minVal) * 0.1
        return (minVal - padding)...(maxVal + padding)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Selection info header
            if let selected = selectedDataPoint {
                selectedDataHeader(selected)
            }

            // Main chart
            Chart {
                // Optimal TSB zone shading
                if showingTSB {
                    RectangleMark(
                        xStart: .value("Start", filteredData.first?.date ?? Date()),
                        xEnd: .value("End", filteredData.last?.date ?? Date()),
                        yStart: .value("Low", -10),
                        yEnd: .value("High", 15)
                    )
                    .foregroundStyle(.green.opacity(0.08))
                }

                // Zero line
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.gray.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 1))

                // CTL (Fitness) line with gradient
                if showingCTL {
                    ForEach(filteredData) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            yStart: .value("Base", yAxisDomain.lowerBound),
                            yEnd: .value("CTL", point.ctl)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.chartFitness.opacity(0.15), Color.chartFitness.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    ForEach(filteredData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("CTL", point.ctl),
                            series: .value("Metric", "CTL")
                        )
                        .foregroundStyle(Color.chartFitness)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }
                }

                // ATL (Fatigue) line with gradient
                if showingATL {
                    ForEach(filteredData) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            yStart: .value("Base", yAxisDomain.lowerBound),
                            yEnd: .value("ATL", point.atl)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.chartFatigue.opacity(0.1), Color.chartFatigue.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .interpolationMethod(.catmullRom)
                    }

                    ForEach(filteredData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("ATL", point.atl),
                            series: .value("Metric", "ATL")
                        )
                        .foregroundStyle(Color.chartFatigue)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .interpolationMethod(.catmullRom)
                    }
                }

                // TSB (Form) area
                if showingTSB {
                    ForEach(filteredData) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            yStart: .value("Zero", 0),
                            yEnd: .value("TSB", point.tsb)
                        )
                        .foregroundStyle(tsbGradient(point.tsb))
                        .opacity(0.3)
                    }

                    ForEach(filteredData) { point in
                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("TSB", point.tsb),
                            series: .value("Metric", "TSB")
                        )
                        .foregroundStyle(tsbColor(point.tsb))
                        .lineStyle(StrokeStyle(lineWidth: 1.5))
                    }
                }

                // Selection indicator
                if let selected = selectedDataPoint {
                    RuleMark(x: .value("Selected", selected.date))
                        .foregroundStyle(.gray.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    if showingCTL {
                        PointMark(x: .value("Date", selected.date), y: .value("CTL", selected.ctl))
                            .foregroundStyle(.blue)
                            .symbolSize(80)
                    }
                    if showingATL {
                        PointMark(x: .value("Date", selected.date), y: .value("ATL", selected.atl))
                            .foregroundStyle(.pink)
                            .symbolSize(80)
                    }
                    if showingTSB {
                        PointMark(x: .value("Date", selected.date), y: .value("TSB", selected.tsb))
                            .foregroundStyle(tsbColor(selected.tsb))
                            .symbolSize(80)
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic) { value in
                    AxisGridLine()
                    AxisValueLabel(format: dateFormat)
                        .font(.caption2)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        Text("\(value.as(Double.self) ?? 0, specifier: "%.0f")")
                            .font(.caption2)
                    }
                }
            }
            .chartYScale(domain: yAxisDomain)
            .chartLegend(position: .top)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let x = value.location.x
                                    if let date: Date = proxy.value(atX: x) {
                                        selectedDataPoint = findClosest(to: date)
                                    }
                                }
                                .onEnded { _ in
                                    // Keep selection visible
                                }
                        )
                }
            }

            // Legend and controls
            legendControls
        }
    }

    @ViewBuilder
    private func selectedDataHeader(_ point: PMCDataPoint) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(point.date, style: .date)
                    .font(.headline)

                HStack(spacing: 16) {
                    if showingCTL {
                        MetricPill(label: "Fitness", value: String(format: "%.0f", point.ctl), color: .blue)
                    }
                    if showingATL {
                        MetricPill(label: "Fatigue", value: String(format: "%.0f", point.atl), color: .pink)
                    }
                    if showingTSB {
                        MetricPill(label: "Form", value: String(format: "%+.0f", point.tsb), color: tsbColor(point.tsb))
                    }
                }
            }

            Spacer()

            if let acwr = point.acwr {
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ACWR")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.2f", acwr))
                        .font(.headline)
                        .foregroundStyle(acwrColor(acwr))
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var legendControls: some View {
        HStack(spacing: 16) {
            // Toggle buttons
            TogglePill(isOn: $showingCTL, label: "Fitness", color: .blue)
            TogglePill(isOn: $showingATL, label: "Fatigue", color: .pink)
            TogglePill(isOn: $showingTSB, label: "Form", color: .green)

            Spacer()

            // Date range picker
            Picker("Range", selection: $selectedDateRange) {
                ForEach(ChartDateRange.allCases, id: \.self) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
    }

    private func tsbColor(_ tsb: Double) -> Color {
        Color.forTSB(tsb)
    }

    private func tsbGradient(_ tsb: Double) -> LinearGradient {
        let color = tsbColor(tsb)
        return LinearGradient(
            colors: [color, .clear],
            startPoint: tsb >= 0 ? .top : .bottom,
            endPoint: tsb >= 0 ? .bottom : .top
        )
    }

    private func acwrColor(_ acwr: Double) -> Color {
        switch acwr {
        case 0.8...1.3: return .green
        case 0.5..<0.8: return .blue
        case 1.3..<1.5: return .orange
        default: return .red
        }
    }

    private func findClosest(to date: Date) -> PMCDataPoint? {
        filteredData.min(by: { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) })
    }

    private var dateFormat: Date.FormatStyle {
        switch selectedDateRange {
        case .week: return .dateTime.weekday(.abbreviated)
        case .month: return .dateTime.day()
        case .quarter, .year: return .dateTime.month(.abbreviated)
        case .all: return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }
}

/// Small pill showing a metric value
struct MetricPill: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }
}

/// Toggle button for chart layers
struct TogglePill: View {
    @Binding var isOn: Bool
    let label: String
    let color: Color

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(isOn ? color : .gray)
                    .frame(width: 8, height: 8)
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isOn ? color.opacity(0.15) : Color.gray.opacity(0.1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    let sampleData: [PMCDataPoint] = (0..<90).map { day in
        let date = Calendar.current.date(byAdding: .day, value: -89 + day, to: Date())!
        let baseCTL = 65 + Double(day) * 0.1
        let baseATL = 70 + sin(Double(day) * 0.3) * 15
        return PMCDataPoint(
            date: date,
            tss: Double.random(in: 30...120),
            ctl: baseCTL + Double.random(in: -3...3),
            atl: baseATL + Double.random(in: -5...5),
            tsb: baseCTL - baseATL + Double.random(in: -5...5)
        )
    }

    PMCChart(
        data: sampleData,
        selectedDateRange: .constant(.month)
    )
    .frame(height: 400)
    .padding()
}
