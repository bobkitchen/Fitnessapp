//
//  TrainingRecommendationService.swift
//  FitnessApp
//
//  Extracts training recommendation logic from views.
//  Single source of truth for generating recommendations and workout suggestions.
//

import Foundation

/// Service for generating training recommendations based on readiness and metrics.
/// Extracts business logic from views to maintain separation of concerns.
struct TrainingRecommendationService {

    // MARK: - Recommendation Generation

    /// Generate a training recommendation based on current readiness level.
    /// - Parameters:
    ///   - readiness: The athlete's current training readiness level
    ///   - hasMetrics: Whether the athlete has any metrics data yet
    /// - Returns: A recommendation string explaining what the athlete should do
    static func generateRecommendation(
        for readiness: TrainingReadiness,
        hasMetrics: Bool
    ) -> String {
        guard hasMetrics else {
            return "No data available yet. Complete your first workout to get personalized recommendations."
        }

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

    /// Suggest a specific workout type based on readiness level.
    /// - Parameters:
    ///   - readiness: The athlete's current training readiness level
    ///   - hasMetrics: Whether the athlete has any metrics data yet
    /// - Returns: A workout suggestion string, or nil if no suggestion available
    static func suggestWorkout(
        for readiness: TrainingReadiness,
        hasMetrics: Bool
    ) -> String? {
        guard hasMetrics else { return nil }

        switch readiness {
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

    // MARK: - Baseline Calculations

    /// Calculate the baseline (average) value from an array of metrics.
    /// - Parameter values: Array of metric values
    /// - Returns: The average, or nil if no values provided
    static func calculateBaseline(from values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Calculate HRV baseline from daily metrics.
    /// - Parameter metrics: Array of DailyMetrics for the baseline period
    /// - Returns: Average HRV value, or nil if no HRV data available
    static func calculateHRVBaseline(from metrics: [DailyMetrics]) -> Double? {
        let values = metrics.compactMap { $0.hrvRMSSD }
        return calculateBaseline(from: values)
    }

    /// Calculate resting heart rate baseline from daily metrics.
    /// - Parameter metrics: Array of DailyMetrics for the baseline period
    /// - Returns: Average RHR value, or nil if no RHR data available
    static func calculateRHRBaseline(from metrics: [DailyMetrics]) -> Double? {
        let values = metrics.compactMap { $0.restingHR }.map { Double($0) }
        return calculateBaseline(from: values)
    }

    // MARK: - Trend Calculation

    /// Calculate a trend from recent metrics.
    /// - Parameters:
    ///   - metrics: Array of DailyMetrics sorted by date ascending
    ///   - keyPath: The metric to analyze
    ///   - threshold: Minimum change to indicate a trend (default 1)
    /// - Returns: The trend direction
    static func calculateTrend(
        from metrics: [DailyMetrics],
        keyPath: KeyPath<DailyMetrics, Double>,
        threshold: Double = 1.0
    ) -> Trend {
        guard metrics.count >= 2 else { return .stable }

        let recent = Array(metrics.suffix(2))
        let change = recent[1][keyPath: keyPath] - recent[0][keyPath: keyPath]

        if change > threshold { return .up }
        if change < -threshold { return .down }
        return .stable
    }

    // MARK: - Weekly Stats

    /// Calculate weekly workout statistics.
    /// - Parameters:
    ///   - workouts: All workout records
    ///   - daysBack: Number of days to include (default 7)
    /// - Returns: Tuple of (totalTSS, totalHours, workoutCount)
    static func calculateWeeklyStats(
        from workouts: [WorkoutRecord],
        daysBack: Int = 7
    ) -> (tss: Double, hours: Double, count: Int) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        let recentWorkouts = workouts.filter { $0.startDate >= cutoffDate }

        let tss = recentWorkouts.reduce(0) { $0 + $1.tss }
        let hours = recentWorkouts.reduce(0) { $0 + $1.durationSeconds } / 3600
        let count = recentWorkouts.count

        return (tss, hours, count)
    }

    /// Calculate weekly TSS breakdown by activity category.
    /// - Parameters:
    ///   - workouts: All workout records
    ///   - daysBack: Number of days to include (default 7)
    /// - Returns: Dictionary mapping activity category to total TSS
    static func calculateWeeklyByActivity(
        from workouts: [WorkoutRecord],
        daysBack: Int = 7
    ) -> [ActivityCategory: Double] {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        let recentWorkouts = workouts.filter { $0.startDate >= cutoffDate }

        var result: [ActivityCategory: Double] = [:]
        for workout in recentWorkouts {
            result[workout.activityCategory, default: 0] += workout.tss
        }
        return result
    }

    // MARK: - Date Range Helpers

    /// Get the date N days ago from today.
    /// - Parameter days: Number of days back
    /// - Returns: Date representing N days ago
    static func daysAgo(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    }

    /// Filter metrics to last N days.
    /// - Parameters:
    ///   - metrics: Array of DailyMetrics
    ///   - days: Number of days to include
    /// - Returns: Filtered and sorted metrics
    static func filterMetrics(
        _ metrics: [DailyMetrics],
        lastDays days: Int
    ) -> [DailyMetrics] {
        let cutoff = daysAgo(days)
        return metrics
            .filter { $0.date >= cutoff }
            .sorted { $0.date < $1.date }
    }
}
