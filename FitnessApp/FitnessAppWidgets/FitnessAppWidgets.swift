import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Widget Bundle

@main
struct FitnessAppWidgets: WidgetBundle {
    var body: some Widget {
        PMCWidget()
        ReadinessWidget()
        FormWidget()
    }
}

// MARK: - Timeline Entry

struct PMCEntry: TimelineEntry {
    let date: Date
    let ctl: Double
    let atl: Double
    let tsb: Double
    let readiness: Int?
    let configuration: ConfigurationAppIntent
}

// MARK: - App Intent Configuration

struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configuration"
    static var description: IntentDescription = "Configure the fitness widget"
}

// MARK: - Timeline Provider

struct PMCProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PMCEntry {
        PMCEntry(
            date: Date(),
            ctl: 72,
            atl: 85,
            tsb: -13,
            readiness: 75,
            configuration: ConfigurationAppIntent()
        )
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> PMCEntry {
        await getCurrentEntry(configuration: configuration)
    }

    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<PMCEntry> {
        let entry = await getCurrentEntry(configuration: configuration)

        // Update hourly
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date())!
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func getCurrentEntry(configuration: ConfigurationAppIntent) async -> PMCEntry {
        // In a real implementation, fetch from shared App Group container
        // For now, return sample data
        return PMCEntry(
            date: Date(),
            ctl: UserDefaults(suiteName: "group.com.bobk.FitnessApp")?.double(forKey: "currentCTL") ?? 72,
            atl: UserDefaults(suiteName: "group.com.bobk.FitnessApp")?.double(forKey: "currentATL") ?? 85,
            tsb: UserDefaults(suiteName: "group.com.bobk.FitnessApp")?.double(forKey: "currentTSB") ?? -13,
            readiness: UserDefaults(suiteName: "group.com.bobk.FitnessApp")?.integer(forKey: "currentReadiness"),
            configuration: configuration
        )
    }
}

// MARK: - PMC Widget (Medium/Large)

struct PMCWidget: Widget {
    let kind: String = "PMCWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: PMCProvider()) { entry in
            PMCWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("PMC Overview")
        .description("View your fitness, fatigue, and form at a glance.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct PMCWidgetView: View {
    let entry: PMCEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.blue)
                Text("Performance")
                    .font(.headline)
                Spacer()
                Text(entry.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Metrics row
            HStack(spacing: 20) {
                MetricView(
                    title: "Fitness",
                    value: String(format: "%.0f", entry.ctl),
                    color: .blue
                )

                MetricView(
                    title: "Fatigue",
                    value: String(format: "%.0f", entry.atl),
                    color: .pink
                )

                MetricView(
                    title: "Form",
                    value: String(format: "%+.0f", entry.tsb),
                    color: formColor
                )
            }

            // Form status
            HStack {
                Circle()
                    .fill(formColor)
                    .frame(width: 8, height: 8)
                Text(formStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let readiness = entry.readiness {
                    Text("Readiness: \(readiness)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
    }

    private var formColor: Color {
        switch entry.tsb {
        case 15...: return .green
        case 5..<15: return .teal
        case -10..<5: return .blue
        case -25..<(-10): return .orange
        default: return .red
        }
    }

    private var formStatus: String {
        switch entry.tsb {
        case 15...: return "Very Fresh"
        case 5..<15: return "Fresh"
        case -10..<5: return "Neutral"
        case -25..<(-10): return "Tired"
        default: return "Very Tired"
        }
    }
}

struct MetricView: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Readiness Widget (Small)

struct ReadinessWidget: Widget {
    let kind: String = "ReadinessWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: PMCProvider()) { entry in
            ReadinessWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Readiness")
        .description("Your training readiness score.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct ReadinessWidgetView: View {
    let entry: PMCEntry

    var body: some View {
        VStack(spacing: 8) {
            // Readiness ring
            ZStack {
                Circle()
                    .stroke(readinessColor.opacity(0.2), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: Double(entry.readiness ?? 75) / 100)
                    .stroke(readinessColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 0) {
                    Text("\(entry.readiness ?? 75)")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Ready")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 80, height: 80)

            Text(readinessStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var readinessColor: Color {
        guard let readiness = entry.readiness else { return .blue }
        switch readiness {
        case 80...100: return .green
        case 60..<80: return .blue
        case 40..<60: return .orange
        default: return .red
        }
    }

    private var readinessStatus: String {
        guard let readiness = entry.readiness else { return "Normal" }
        switch readiness {
        case 80...100: return "Fully Ready"
        case 60..<80: return "Mostly Ready"
        case 40..<60: return "Reduced"
        default: return "Rest"
        }
    }
}

// MARK: - Form Widget (Lock Screen)

struct FormWidget: Widget {
    let kind: String = "FormWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: PMCProvider()) { entry in
            FormWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Form")
        .description("Your current training form (TSB).")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct FormWidgetView: View {
    let entry: PMCEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 2) {
                Text(String(format: "%+.0f", entry.tsb))
                    .font(.headline)
                    .fontWeight(.bold)

                Text("TSB")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Previews

#Preview("PMC Medium", as: .systemMedium) {
    PMCWidget()
} timeline: {
    PMCEntry(date: .now, ctl: 72, atl: 85, tsb: -13, readiness: 75, configuration: ConfigurationAppIntent())
    PMCEntry(date: .now, ctl: 75, atl: 80, tsb: -5, readiness: 82, configuration: ConfigurationAppIntent())
}

#Preview("Readiness Small", as: .systemSmall) {
    ReadinessWidget()
} timeline: {
    PMCEntry(date: .now, ctl: 72, atl: 85, tsb: -13, readiness: 75, configuration: ConfigurationAppIntent())
}

#Preview("Form Circular", as: .accessoryCircular) {
    FormWidget()
} timeline: {
    PMCEntry(date: .now, ctl: 72, atl: 85, tsb: -13, readiness: 75, configuration: ConfigurationAppIntent())
}
