import Foundation

/// Analyzes wellness data to calculate recovery scores and training readiness
struct WellnessAnalyzer {

    // MARK: - Baseline Calculations

    /// Calculate rolling baseline for a metric
    ///
    /// - Parameters:
    ///   - values: Historical values (newest last)
    ///   - days: Number of days for baseline (default 7)
    /// - Returns: Average baseline value
    static func calculateBaseline(values: [Double], days: Int = 7) -> Double? {
        guard !values.isEmpty else { return nil }
        let subset = Array(values.suffix(days))
        return subset.reduce(0, +) / Double(subset.count)
    }

    /// Calculate baseline with standard deviation
    static func calculateBaselineWithSD(values: [Double], days: Int = 7) -> (mean: Double, sd: Double)? {
        guard values.count >= days else { return nil }
        let subset = Array(values.suffix(days))
        let mean = subset.reduce(0, +) / Double(subset.count)
        let variance = subset.reduce(0) { $0 + pow($1 - mean, 2) } / Double(subset.count)
        return (mean, sqrt(variance))
    }

    // MARK: - HRV Analysis

    /// Analyze HRV relative to baseline
    ///
    /// - Parameters:
    ///   - currentHRV: Today's HRV (RMSSD in ms)
    ///   - baseline7Day: 7-day baseline values
    ///   - baseline30Day: 30-day baseline values (optional for trend)
    /// - Returns: HRV analysis result
    static func analyzeHRV(
        currentHRV: Double,
        baseline7Day: [Double],
        baseline30Day: [Double]? = nil
    ) -> HRVAnalysis {
        guard let stats = calculateBaselineWithSD(values: baseline7Day, days: 7) else {
            return HRVAnalysis(
                score: 50,
                status: .unknown,
                percentOfBaseline: nil,
                trend: .stable
            )
        }

        let percentOfBaseline = currentHRV / stats.mean
        let zScore = (currentHRV - stats.mean) / max(stats.sd, 1)

        // Score based on z-score
        // +2 SD = 100, mean = 70, -2 SD = 40
        let score = max(0, min(100, 70 + (zScore * 15)))

        let status: HRVStatus
        switch percentOfBaseline {
        case 1.15...: status = .elevated
        case 0.95..<1.15: status = .normal
        case 0.85..<0.95: status = .belowNormal
        default: status = .low
        }

        // Calculate trend from 30-day data if available
        let trend: Trend
        if let longBaseline = baseline30Day,
           let longStats = calculateBaselineWithSD(values: longBaseline, days: 30) {
            let shortMean = stats.mean
            if shortMean > longStats.mean * 1.05 {
                trend = .up
            } else if shortMean < longStats.mean * 0.95 {
                trend = .down
            } else {
                trend = .stable
            }
        } else {
            trend = .stable
        }

        return HRVAnalysis(
            score: score,
            status: status,
            percentOfBaseline: percentOfBaseline,
            trend: trend,
            sevenDayMean: stats.mean,
            standardDeviation: stats.sd
        )
    }

    // MARK: - Resting Heart Rate Analysis

    /// Analyze resting HR relative to baseline
    /// Note: Lower RHR is generally better; elevated RHR indicates stress/fatigue
    static func analyzeRestingHR(
        currentRHR: Int,
        baseline7Day: [Double]
    ) -> RHRAnalysis {
        guard let stats = calculateBaselineWithSD(values: baseline7Day, days: 7) else {
            return RHRAnalysis(score: 50, status: .unknown, deviationFromBaseline: 0)
        }

        let deviation = Double(currentRHR) - stats.mean
        let zScore = deviation / max(stats.sd, 1)

        // Score: lower is better
        // -2 SD = 100 (very low, well recovered)
        // mean = 70 (normal)
        // +2 SD = 40 (elevated, fatigued)
        let score = max(0, min(100, 70 - (zScore * 15)))

        let status: RHRStatus
        switch zScore {
        case ...(-1.5): status = .veryLow
        case -1.5..<(-0.5): status = .low
        case -0.5..<0.5: status = .normal
        case 0.5..<1.5: status = .elevated
        default: status = .high
        }

        return RHRAnalysis(
            score: score,
            status: status,
            deviationFromBaseline: deviation,
            sevenDayMean: stats.mean
        )
    }

    // MARK: - Sleep Analysis

    /// Analyze sleep quality and duration
    static func analyzeSleep(
        hoursSlept: Double,
        sleepQuality: Double?,   // 0-1 if available
        deepSleepMinutes: Double?,
        remSleepMinutes: Double?,
        efficiency: Double?       // 0-1
    ) -> SleepAnalysis {
        var score = 0.0
        var factors = 0

        // Duration score (target 7-9 hours)
        let durationScore: Double
        switch hoursSlept {
        case 7.5...8.5: durationScore = 100
        case 7..<7.5, 8.5..<9: durationScore = 85
        case 6.5..<7, 9..<9.5: durationScore = 70
        case 6..<6.5, 9.5..<10: durationScore = 55
        case 5..<6: durationScore = 40
        default: durationScore = 25
        }
        score += durationScore
        factors += 1

        // Quality score (if available)
        if let quality = sleepQuality {
            score += quality * 100
            factors += 1
        }

        // Deep sleep score (target 60-120 minutes, ~15-20% of 7-8 hours)
        if let deep = deepSleepMinutes {
            let deepScore: Double
            switch deep {
            case 60...120: deepScore = 100
            case 45..<60, 120..<150: deepScore = 80
            case 30..<45, 150..<180: deepScore = 60
            default: deepScore = 40
            }
            score += deepScore
            factors += 1
        }

        // REM score (target 90-150 minutes, ~20-25% of 7-8 hours)
        if let rem = remSleepMinutes {
            let remScore: Double
            switch rem {
            case 90...150: remScore = 100
            case 60..<90, 150..<180: remScore = 80
            case 45..<60: remScore = 60
            default: remScore = 40
            }
            score += remScore
            factors += 1
        }

        // Efficiency score
        if let eff = efficiency {
            let effScore = eff * 100
            score += effScore
            factors += 1
        }

        let finalScore = factors > 0 ? score / Double(factors) : 50

        let status: SleepStatus
        switch finalScore {
        case 80...100: status = .excellent
        case 65..<80: status = .good
        case 50..<65: status = .fair
        default: status = .poor
        }

        return SleepAnalysis(
            score: finalScore,
            status: status,
            hoursSlept: hoursSlept,
            deepSleepMinutes: deepSleepMinutes,
            remSleepMinutes: remSleepMinutes,
            efficiency: efficiency
        )
    }

    // MARK: - Composite Readiness Score

    /// Calculate overall training readiness from multiple inputs
    ///
    /// Weights:
    /// - HRV: 30%
    /// - Sleep: 25%
    /// - Resting HR: 15%
    /// - Recovery time (days since hard effort): 15%
    /// - Stress/mindfulness: 15%
    static func calculateReadinessScore(
        hrvAnalysis: HRVAnalysis?,
        sleepAnalysis: SleepAnalysis?,
        rhrAnalysis: RHRAnalysis?,
        daysSinceHardEffort: Int?,
        tsb: Double?,
        mindfulMinutes: Double?,
        stateOfMind: Int?
    ) -> ReadinessResult {
        var weightedScore = 0.0
        var totalWeight = 0.0

        // HRV (30%)
        if let hrv = hrvAnalysis {
            weightedScore += hrv.score * 0.30
            totalWeight += 0.30
        }

        // Sleep (25%)
        if let sleep = sleepAnalysis {
            weightedScore += sleep.score * 0.25
            totalWeight += 0.25
        }

        // RHR (15%)
        if let rhr = rhrAnalysis {
            weightedScore += rhr.score * 0.15
            totalWeight += 0.15
        }

        // Recovery time (15%)
        if let days = daysSinceHardEffort {
            let recoveryScore: Double
            switch days {
            case 0: recoveryScore = 40  // Just trained hard
            case 1: recoveryScore = 60
            case 2: recoveryScore = 80
            default: recoveryScore = 100
            }
            weightedScore += recoveryScore * 0.15
            totalWeight += 0.15
        }

        // TSB contribution (incorporated into recovery)
        if let tsb = tsb {
            let tsbScore: Double
            switch tsb {
            case 15...: tsbScore = 100
            case 5..<15: tsbScore = 85
            case -10..<5: tsbScore = 70
            case -25..<(-10): tsbScore = 50
            default: tsbScore = 30
            }
            weightedScore += tsbScore * 0.10
            totalWeight += 0.10
        }

        // Stress/mindfulness (5%)
        var stressScore = 50.0  // Default neutral
        if let mindful = mindfulMinutes, mindful > 0 {
            stressScore = min(100, 50 + mindful * 2)  // Bonus for mindfulness
        }
        if let mood = stateOfMind {
            // Assuming 1-5 scale, 5 being best
            stressScore = Double(mood) * 20
        }
        weightedScore += stressScore * 0.05
        totalWeight += 0.05

        // Normalize score
        let finalScore = totalWeight > 0 ? weightedScore / totalWeight : 50

        let readiness = TrainingReadiness(score: finalScore)

        // Generate insights
        var insights: [String] = []

        if let hrv = hrvAnalysis {
            if hrv.status == .low {
                insights.append("HRV is significantly below baseline - consider rest")
            } else if hrv.status == .elevated {
                insights.append("HRV is elevated - good recovery indicator")
            }
        }

        if let sleep = sleepAnalysis {
            if sleep.status == .poor {
                insights.append("Sleep quality was poor - may affect performance")
            }
            if let deep = sleep.deepSleepMinutes, deep < 45 {
                insights.append("Limited deep sleep may slow physical recovery")
            }
        }

        if let rhr = rhrAnalysis, rhr.status == .high {
            insights.append("Elevated resting HR suggests accumulated fatigue")
        }

        if let tsb = tsb, tsb < -20 {
            insights.append("High fatigue accumulated - recovery recommended")
        }

        return ReadinessResult(
            score: finalScore,
            readiness: readiness,
            components: ReadinessComponents(
                hrvScore: hrvAnalysis?.score,
                sleepScore: sleepAnalysis?.score,
                rhrScore: rhrAnalysis?.score,
                recoveryScore: daysSinceHardEffort.map { days in
                    switch days {
                    case 0: return 40.0
                    case 1: return 60.0
                    case 2: return 80.0
                    default: return 100.0
                    }
                },
                stressScore: stressScore
            ),
            insights: insights
        )
    }
}

// MARK: - Analysis Result Types

struct HRVAnalysis {
    let score: Double           // 0-100
    let status: HRVStatus
    let percentOfBaseline: Double?
    let trend: Trend
    var sevenDayMean: Double?
    var standardDeviation: Double?
}

enum HRVStatus: String {
    case elevated = "Elevated"
    case normal = "Normal"
    case belowNormal = "Below Normal"
    case low = "Low"
    case unknown = "Unknown"

    var color: String {
        switch self {
        case .elevated: return "green"
        case .normal: return "blue"
        case .belowNormal: return "orange"
        case .low: return "red"
        case .unknown: return "gray"
        }
    }
}

struct RHRAnalysis {
    let score: Double           // 0-100
    let status: RHRStatus
    let deviationFromBaseline: Double
    var sevenDayMean: Double?
}

enum RHRStatus: String {
    case veryLow = "Very Low"
    case low = "Low"
    case normal = "Normal"
    case elevated = "Elevated"
    case high = "High"
    case unknown = "Unknown"

    var description: String {
        switch self {
        case .veryLow: return "Exceptionally recovered"
        case .low: return "Well recovered"
        case .normal: return "Normal range"
        case .elevated: return "Slightly elevated - possible fatigue"
        case .high: return "Elevated - recovery recommended"
        case .unknown: return "Insufficient data"
        }
    }
}

struct SleepAnalysis {
    let score: Double           // 0-100
    let status: SleepStatus
    let hoursSlept: Double
    let deepSleepMinutes: Double?
    let remSleepMinutes: Double?
    let efficiency: Double?
}

enum SleepStatus: String {
    case excellent = "Excellent"
    case good = "Good"
    case fair = "Fair"
    case poor = "Poor"

    var color: String {
        switch self {
        case .excellent: return "green"
        case .good: return "blue"
        case .fair: return "orange"
        case .poor: return "red"
        }
    }
}

struct ReadinessResult {
    let score: Double           // 0-100
    let readiness: TrainingReadiness
    let components: ReadinessComponents
    let insights: [String]
}

struct ReadinessComponents {
    let hrvScore: Double?
    let sleepScore: Double?
    let rhrScore: Double?
    let recoveryScore: Double?
    let stressScore: Double?
}
