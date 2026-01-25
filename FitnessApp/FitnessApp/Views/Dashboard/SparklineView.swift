import SwiftUI
import Charts

/// A compact inline sparkline chart showing 7-day trend
struct SparklineView: View {
    let data: [Double]
    let color: Color
    let showGradient: Bool

    init(data: [Double], color: Color = .accentPrimary, showGradient: Bool = true) {
        self.data = data
        self.color = color
        self.showGradient = showGradient
    }

    var body: some View {
        Chart {
            ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Day", index),
                    y: .value("Value", value)
                )
                .foregroundStyle(color)
                .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.catmullRom)

                if showGradient {
                    AreaMark(
                        x: .value("Day", index),
                        y: .value("Value", value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .chartYScale(domain: yDomain)
    }

    private var yDomain: ClosedRange<Double> {
        guard let min = data.min(), let max = data.max() else {
            return 0...100
        }
        let padding = (max - min) * 0.2
        return (min - padding)...(max + padding)
    }
}

// MARK: - Trend Sparkline with Direction Indicator

/// A sparkline with trend direction arrow
struct TrendSparkline: View {
    let data: [Double]
    let trend: Trend?
    let color: Color

    init(data: [Double], trend: Trend? = nil, color: Color = .chartFitness) {
        self.data = data
        self.trend = trend ?? Self.calculateTrend(from: data)
        self.color = color
    }

    var body: some View {
        HStack(spacing: Spacing.xs) {
            SparklineView(data: data, color: color, showGradient: false)
                .frame(height: 20)

            if let trend {
                Image(systemName: trend.icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(trendColor)
            }
        }
    }

    private var trendColor: Color {
        guard let trend else { return .textTertiary }
        switch trend {
        case .up: return .statusExcellent
        case .down: return .statusLow
        case .stable: return .textTertiary
        }
    }

    private static func calculateTrend(from data: [Double]) -> Trend? {
        guard data.count >= 2 else { return nil }
        let recent = data.suffix(3).reduce(0, +) / Double(min(3, data.count))
        let older = data.prefix(3).reduce(0, +) / Double(min(3, data.count))
        let change = recent - older
        if change > older * 0.05 { return .up }
        if change < -older * 0.05 { return .down }
        return .stable
    }
}

// MARK: - PMC Sparkline (CTL/ATL/TSB)

/// Specialized sparkline for PMC data showing all three metrics
struct PMCSparkline: View {
    let ctlData: [Double]
    let atlData: [Double]
    let tsbData: [Double]

    var body: some View {
        Chart {
            // CTL line
            ForEach(Array(ctlData.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Day", index),
                    y: .value("CTL", value),
                    series: .value("Metric", "CTL")
                )
                .foregroundStyle(Color.chartFitness)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            // ATL line
            ForEach(Array(atlData.enumerated()), id: \.offset) { index, value in
                LineMark(
                    x: .value("Day", index),
                    y: .value("ATL", value),
                    series: .value("Metric", "ATL")
                )
                .foregroundStyle(Color.chartFatigue)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.catmullRom)
            }

            // Zero reference for TSB
            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.textTertiary.opacity(0.3))
                .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 2]))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: Spacing.lg) {
        // Basic sparkline
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Basic Sparkline")
                .sectionHeaderStyle()

            SparklineView(
                data: [65, 68, 70, 72, 71, 74, 78],
                color: .accentPrimary
            )
            .frame(height: 40)
            .padding()
            .cardBackground()
        }

        // Trend sparkline
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Trend Sparklines")
                .sectionHeaderStyle()

            HStack(spacing: Spacing.md) {
                VStack {
                    TrendSparkline(
                        data: [65, 68, 70, 72, 74, 76, 78],
                        color: .chartFitness
                    )
                    Text("Upward")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)

                VStack {
                    TrendSparkline(
                        data: [78, 76, 74, 72, 70, 68, 65],
                        color: .chartFatigue
                    )
                    Text("Downward")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)

                VStack {
                    TrendSparkline(
                        data: [70, 71, 70, 69, 70, 71, 70],
                        color: .statusModerate
                    )
                    Text("Stable")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
            .cardBackground()
        }

        // PMC sparkline
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("PMC Sparkline")
                .sectionHeaderStyle()

            PMCSparkline(
                ctlData: [68, 69, 70, 71, 72, 73, 74],
                atlData: [75, 78, 82, 80, 77, 75, 73],
                tsbData: [-7, -9, -12, -9, -5, -2, 1]
            )
            .frame(height: 60)
            .padding()
            .cardBackground()
        }
    }
    .padding()
    .background(Color.backgroundPrimary)
}
