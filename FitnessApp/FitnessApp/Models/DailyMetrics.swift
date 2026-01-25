import Foundation
import SwiftData

@Model
final class DailyMetrics {
    var id: UUID
    var date: Date
    var createdAt: Date
    var updatedAt: Date

    // MARK: - PMC Metrics
    var totalTSS: Double                    // Total Training Stress Score for the day
    var ctl: Double                         // Chronic Training Load (Fitness)
    var atl: Double                         // Acute Training Load (Fatigue)
    var tsb: Double                         // Training Stress Balance (Form)

    // MARK: - Recovery Indicators
    var hrvRMSSD: Double?                   // Heart Rate Variability (RMSSD in ms)
    var hrvSDNN: Double?                    // HRV SDNN variant
    var restingHR: Int?                     // Resting Heart Rate (bpm)
    var respiratoryRate: Double?            // Breaths per minute
    var oxygenSaturation: Double?           // SpO2 percentage
    var bodyTemperature: Double?            // Celsius (if available)

    // MARK: - Sleep Data
    var sleepHours: Double?                 // Total sleep duration
    var sleepQuality: Double?               // 0-1 composite quality score
    var deepSleepMinutes: Double?           // Deep sleep stage duration
    var remSleepMinutes: Double?            // REM sleep stage duration
    var coreSleepMinutes: Double?           // Core/light sleep duration
    var awakeMinutes: Double?               // Time awake during sleep period
    var sleepEfficiency: Double?            // Time asleep / time in bed (0-1)
    var sleepStartTime: Date?               // When sleep began
    var sleepEndTime: Date?                 // When sleep ended

    // MARK: - Stress & Mental Wellness
    var mindfulMinutes: Double?             // Meditation/breathing session time
    var stateOfMind: Int?                   // Mood rating (1-5 scale)
    var timeInDaylightMinutes: Double?      // Daylight exposure for circadian health

    // MARK: - Activity Metrics
    var steps: Int?
    var activeCalories: Double?
    var totalCalories: Double?
    var exerciseMinutes: Double?
    var standHours: Int?
    var flightsClimbed: Int?
    var walkingSpeed: Double?               // Average walking speed m/s

    // MARK: - Body Metrics
    var vo2Max: Double?                     // Cardiorespiratory fitness ml/kg/min
    var weight: Double?                     // kg
    var bodyFatPercentage: Double?

    // MARK: - Derived Scores
    var readinessScore: Double?             // 0-100 composite readiness
    var recoveryScore: Double?              // 0-100 recovery status
    var strainScore: Double?                // Daily strain/load score

    // MARK: - Metadata
    var sourceRaw: String
    var source: MetricSource {
        get { MetricSource(rawValue: sourceRaw) ?? .calculated }
        set { sourceRaw = newValue.rawValue }
    }

    var notes: String?

    init(
        id: UUID = UUID(),
        date: Date,
        totalTSS: Double = 0,
        ctl: Double = 0,
        atl: Double = 0,
        tsb: Double = 0,
        source: MetricSource = .calculated
    ) {
        self.id = id
        self.date = Calendar.current.startOfDay(for: date)
        self.createdAt = Date()
        self.updatedAt = Date()
        self.totalTSS = totalTSS
        self.ctl = ctl
        self.atl = atl
        self.tsb = tsb
        self.sourceRaw = source.rawValue
    }

    // MARK: - Computed Properties

    /// Training readiness based on readiness score
    var trainingReadiness: TrainingReadiness {
        TrainingReadiness(score: readinessScore ?? 50)
    }

    /// TSB status description
    var formStatus: String {
        switch tsb {
        case 15...: return "Very Fresh"
        case 5..<15: return "Fresh"
        case -10..<5: return "Neutral"
        case -25..<(-10): return "Tired"
        default: return "Very Tired"
        }
    }

    /// CTL trend compared to target
    var fitnessStatus: String {
        switch ctl {
        case 100...: return "Peak"
        case 70..<100: return "High"
        case 40..<70: return "Moderate"
        default: return "Building"
        }
    }

    /// Sleep duration status
    var sleepStatus: String? {
        guard let hours = sleepHours else { return nil }
        switch hours {
        case 8...: return "Excellent"
        case 7..<8: return "Good"
        case 6..<7: return "Fair"
        default: return "Poor"
        }
    }

    /// Total sleep time formatted
    var sleepFormatted: String? {
        guard let hours = sleepHours else { return nil }
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "\(h)h \(m)m"
    }

    /// HRV status relative to typical baseline
    func hrvStatus(baseline: Double) -> String {
        guard let hrv = hrvRMSSD else { return "Unknown" }
        let percentOfBaseline = hrv / baseline
        switch percentOfBaseline {
        case 1.1...: return "Above Normal"
        case 0.9..<1.1: return "Normal"
        case 0.75..<0.9: return "Below Normal"
        default: return "Low"
        }
    }

    /// Acute to chronic workload ratio (injury risk indicator)
    var acuteChronicRatio: Double? {
        guard ctl > 0 else { return nil }
        return atl / ctl
    }

    /// ACWR status for injury risk
    var acwrStatus: String {
        guard let ratio = acuteChronicRatio else { return "Unknown" }
        switch ratio {
        case 0.8...1.3: return "Optimal"
        case 1.3...1.5: return "Caution"
        case 1.5...: return "High Risk"
        default: return "Detraining"
        }
    }
}

// MARK: - Sleep Analysis Helper

extension DailyMetrics {
    /// Calculate sleep quality score from sleep stage data
    func calculateSleepQuality() -> Double {
        var score = 0.0
        var factors = 0

        // Duration factor (target 7-9 hours)
        if let hours = sleepHours {
            let durationScore: Double
            switch hours {
            case 7...9: durationScore = 1.0
            case 6..<7, 9..<10: durationScore = 0.7
            case 5..<6, 10..<11: durationScore = 0.4
            default: durationScore = 0.2
            }
            score += durationScore
            factors += 1
        }

        // Deep sleep factor (target 15-20% of total)
        if let deep = deepSleepMinutes, let total = sleepHours {
            let totalMinutes = total * 60
            let deepPercent = deep / totalMinutes
            let deepScore: Double
            switch deepPercent {
            case 0.15...0.25: deepScore = 1.0
            case 0.10..<0.15, 0.25..<0.30: deepScore = 0.7
            default: deepScore = 0.4
            }
            score += deepScore
            factors += 1
        }

        // REM factor (target 20-25% of total)
        if let rem = remSleepMinutes, let total = sleepHours {
            let totalMinutes = total * 60
            let remPercent = rem / totalMinutes
            let remScore: Double
            switch remPercent {
            case 0.20...0.30: remScore = 1.0
            case 0.15..<0.20, 0.30..<0.35: remScore = 0.7
            default: remScore = 0.4
            }
            score += remScore
            factors += 1
        }

        // Efficiency factor
        if let efficiency = sleepEfficiency {
            let effScore: Double
            switch efficiency {
            case 0.90...1.0: effScore = 1.0
            case 0.80..<0.90: effScore = 0.7
            case 0.70..<0.80: effScore = 0.4
            default: effScore = 0.2
            }
            score += effScore
            factors += 1
        }

        return factors > 0 ? score / Double(factors) : 0.5
    }
}
