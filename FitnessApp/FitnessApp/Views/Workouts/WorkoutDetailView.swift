import SwiftUI
import Charts

/// Detailed view of a single workout
struct WorkoutDetailView: View {
    let workout: WorkoutRecord
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header card
                    headerCard

                    // Key metrics
                    metricsGrid

                    // Heart rate zones (if available)
                    if workout.heartRateZoneDistribution != nil {
                        heartRateZonesCard
                    }

                    // Power/pace details
                    if workout.normalizedPower != nil || workout.normalizedPace != nil {
                        performanceCard
                    }

                    // Running metrics (if available)
                    if hasRunningMetrics {
                        runningMetricsCard
                    }

                    // Notes
                    if let notes = workout.notes, !notes.isEmpty {
                        notesCard(notes)
                    }
                }
                .padding()
            }
            .navigationTitle("Workout Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header Card

    @ViewBuilder
    private var headerCard: some View {
        VStack(spacing: 16) {
            // Activity icon and type
            HStack {
                Image(systemName: workout.activityIcon)
                    .font(.title)
                    .foregroundStyle(activityColor)
                    .frame(width: 50, height: 50)
                    .background(activityColor.opacity(0.15))
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(workout.title ?? workout.activityType)
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(workout.dayOfWeek + ", " + workout.dateFormatted)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(workout.timeFormatted)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            Divider()

            // Main stats row
            HStack {
                StatItem(value: workout.durationFormatted, label: "Duration", icon: "clock")
                Divider().frame(height: 40)

                if let distance = workout.distanceKm {
                    StatItem(value: String(format: "%.2f km", distance), label: "Distance", icon: "arrow.left.arrow.right")
                    Divider().frame(height: 40)
                }

                StatItem(value: String(format: "%.0f", workout.tss), label: "TSS", icon: "flame")
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Metrics Grid

    @ViewBuilder
    private var metricsGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            if let avgHR = workout.averageHeartRate {
                MetricCard(title: "Avg Heart Rate", value: "\(avgHR)", unit: "bpm", icon: "heart.fill", color: .red)
            }

            if let maxHR = workout.maxHeartRate {
                MetricCard(title: "Max Heart Rate", value: "\(maxHR)", unit: "bpm", icon: "heart.fill", color: .red)
            }

            if let avgPower = workout.averagePower {
                MetricCard(title: "Avg Power", value: "\(avgPower)", unit: "W", icon: "bolt.fill", color: .yellow)
            }

            if let np = workout.normalizedPower {
                MetricCard(title: "Normalized Power", value: "\(np)", unit: "W", icon: "bolt.fill", color: .orange)
            }

            if let pace = workout.averagePaceFormatted {
                MetricCard(title: "Avg Pace", value: pace, unit: "", icon: "speedometer", color: .green)
            }

            if let calories = workout.activeCalories {
                MetricCard(title: "Calories", value: String(format: "%.0f", calories), unit: "kcal", icon: "flame.fill", color: .orange)
            }

            if let cadence = workout.averageCadence {
                MetricCard(title: "Avg Cadence", value: "\(cadence)", unit: workout.activityCategory == .bike ? "rpm" : "spm", icon: "metronome", color: .purple)
            }

            MetricCard(
                title: "Intensity Factor",
                value: String(format: "%.2f", workout.intensityFactor),
                unit: "",
                icon: "gauge.with.needle",
                color: .blue
            )
        }
    }

    // MARK: - Heart Rate Zones

    @ViewBuilder
    private var heartRateZonesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Heart Rate Zones")
                .font(.headline)

            let zones = workout.zonePercentages()

            ForEach(zones, id: \.zone) { item in
                HStack {
                    Text("Zone \(item.zone.rawValue)")
                        .font(.caption)
                        .frame(width: 50, alignment: .leading)

                    Text(item.zone.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.gray.opacity(0.2))

                            RoundedRectangle(cornerRadius: 4)
                                .fill(zoneColor(item.zone))
                                .frame(width: max(4, geo.size.width * (item.percentage / 100)))
                        }
                    }
                    .frame(height: 20)

                    Text(String(format: "%.0f%%", item.percentage))
                        .font(.caption)
                        .fontWeight(.medium)
                        .frame(width: 40, alignment: .trailing)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Performance Card

    @ViewBuilder
    private var performanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance")
                .font(.headline)

            HStack(spacing: 20) {
                if let np = workout.normalizedPower, let avg = workout.averagePower {
                    VStack(spacing: 4) {
                        Text("Variability Index")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.2f", Double(np) / Double(avg)))
                            .font(.title3)
                            .fontWeight(.semibold)
                    }
                }

                if workout.intensityFactor > 0 {
                    VStack(spacing: 4) {
                        Text("Intensity")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(workout.intensityLevel)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundStyle(intensityColor)
                    }
                }

                VStack(spacing: 4) {
                    Text("TSS/Hour")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.0f", workout.tssPerHour))
                        .font(.title3)
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)

            // TSS type indicator
            HStack {
                Image(systemName: "info.circle")
                    .font(.caption)
                Text("TSS calculated using \(workout.tssType.description)")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Running Metrics Card

    private var hasRunningMetrics: Bool {
        workout.strideLength != nil ||
        workout.verticalOscillation != nil ||
        workout.groundContactTime != nil ||
        workout.totalAscent != nil
    }

    @ViewBuilder
    private var runningMetricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Running Dynamics")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                if let stride = workout.strideLength {
                    MiniMetric(label: "Stride Length", value: String(format: "%.2f m", stride))
                }
                if let vo = workout.verticalOscillation {
                    MiniMetric(label: "Vertical Osc", value: String(format: "%.1f cm", vo))
                }
                if let gct = workout.groundContactTime {
                    MiniMetric(label: "Ground Contact", value: String(format: "%.0f ms", gct))
                }
                if let ascent = workout.totalAscent {
                    MiniMetric(label: "Elevation Gain", value: String(format: "%.0f m", ascent))
                }
                if let descent = workout.totalDescent {
                    MiniMetric(label: "Elevation Loss", value: String(format: "%.0f m", descent))
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Notes Card

    @ViewBuilder
    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
            Text(notes)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helper Views & Methods

    private var activityColor: Color {
        switch workout.activityCategory {
        case .run: return .orange
        case .bike: return .blue
        case .swim: return .cyan
        case .strength: return .purple
        case .other: return .gray
        }
    }

    private var intensityColor: Color {
        switch workout.intensityFactor {
        case 1.05...: return .red
        case 0.95..<1.05: return .orange
        case 0.85..<0.95: return .yellow
        case 0.75..<0.85: return .green
        default: return .blue
        }
    }

    private func zoneColor(_ zone: HeartRateZone) -> Color {
        switch zone {
        case .zone1: return .blue
        case .zone2: return .green
        case .zone3: return .yellow
        case .zone4: return .orange
        case .zone5: return .red
        }
    }
}

// MARK: - Supporting Views

struct StatItem: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let unit: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MiniMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Preview

#Preview {
    WorkoutDetailView(
        workout: WorkoutRecord(
            activityType: "Cycling",
            activityCategory: .bike,
            title: "Morning Ride",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600),
            durationSeconds: 3600,
            distanceMeters: 32000,
            tss: 75,
            tssType: .power,
            intensityFactor: 0.85
        )
    )
}
