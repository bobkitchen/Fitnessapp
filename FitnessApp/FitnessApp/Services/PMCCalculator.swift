import Foundation
import SwiftData

/// Performance Management Chart (PMC) Calculator
/// Calculates CTL (Chronic Training Load / Fitness), ATL (Acute Training Load / Fatigue),
/// and TSB (Training Stress Balance / Form)
struct PMCCalculator {

    // MARK: - Time Constants

    /// Default time constant for CTL (42 days)
    static let defaultCTLDays: Double = 42

    /// Default time constant for ATL (7 days)
    static let defaultATLDays: Double = 7

    // MARK: - Single Day Calculations

    /// Calculate CTL for today based on yesterday's CTL and today's TSS
    /// CTL_today = CTL_yesterday + (TSS_today - CTL_yesterday) × (1/42)
    ///
    /// - Parameters:
    ///   - previousCTL: Yesterday's CTL value
    ///   - todayTSS: Today's total TSS
    ///   - timeConstant: Time constant in days (default 42)
    /// - Returns: Today's CTL
    static func calculateCTL(
        previousCTL: Double,
        todayTSS: Double,
        timeConstant: Double = defaultCTLDays
    ) -> Double {
        let decayFactor = 1.0 / timeConstant
        return previousCTL + (todayTSS - previousCTL) * decayFactor
    }

    /// Calculate ATL for today based on yesterday's ATL and today's TSS
    /// ATL_today = ATL_yesterday + (TSS_today - ATL_yesterday) × (1/7)
    ///
    /// - Parameters:
    ///   - previousATL: Yesterday's ATL value
    ///   - todayTSS: Today's total TSS
    ///   - timeConstant: Time constant in days (default 7)
    /// - Returns: Today's ATL
    static func calculateATL(
        previousATL: Double,
        todayTSS: Double,
        timeConstant: Double = defaultATLDays
    ) -> Double {
        let decayFactor = 1.0 / timeConstant
        return previousATL + (todayTSS - previousATL) * decayFactor
    }

    /// Calculate TSB (Form) from CTL and ATL
    /// TSB = CTL - ATL
    static func calculateTSB(ctl: Double, atl: Double) -> Double {
        return ctl - atl
    }

    // MARK: - Batch Calculations

    /// Calculate PMC values for a range of days
    ///
    /// - Parameters:
    ///   - dailyTSS: Dictionary of date to total TSS for that day
    ///   - startDate: First date to calculate
    ///   - endDate: Last date to calculate
    ///   - initialCTL: Starting CTL value (default 0)
    ///   - initialATL: Starting ATL value (default 0)
    /// - Returns: Array of PMC data points
    static func calculatePMC(
        dailyTSS: [Date: Double],
        startDate: Date,
        endDate: Date,
        initialCTL: Double = 0,
        initialATL: Double = 0
    ) -> [PMCDataPoint] {
        var results: [PMCDataPoint] = []
        var currentCTL = initialCTL
        var currentATL = initialATL

        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: startDate)
        let finalDate = calendar.startOfDay(for: endDate)

        while currentDate <= finalDate {
            let tss = dailyTSS[currentDate] ?? 0

            currentCTL = calculateCTL(previousCTL: currentCTL, todayTSS: tss)
            currentATL = calculateATL(previousATL: currentATL, todayTSS: tss)
            let tsb = calculateTSB(ctl: currentCTL, atl: currentATL)

            results.append(PMCDataPoint(
                date: currentDate,
                tss: tss,
                ctl: currentCTL,
                atl: currentATL,
                tsb: tsb
            ))

            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        return results
    }

    /// Calculate PMC from workout records
    static func calculatePMC(
        workouts: [WorkoutRecord],
        startDate: Date,
        endDate: Date,
        initialCTL: Double = 0,
        initialATL: Double = 0
    ) -> [PMCDataPoint] {
        // Group workouts by day and sum TSS
        var dailyTSS: [Date: Double] = [:]
        let calendar = Calendar.current

        for workout in workouts {
            let day = calendar.startOfDay(for: workout.startDate)
            dailyTSS[day, default: 0] += workout.tss
        }

        return calculatePMC(
            dailyTSS: dailyTSS,
            startDate: startDate,
            endDate: endDate,
            initialCTL: initialCTL,
            initialATL: initialATL
        )
    }

    // MARK: - Projection

    /// Project future PMC values based on planned training
    ///
    /// - Parameters:
    ///   - currentCTL: Current CTL
    ///   - currentATL: Current ATL
    ///   - plannedDailyTSS: Array of planned TSS values for upcoming days
    /// - Returns: Projected PMC data points
    static func projectPMC(
        currentCTL: Double,
        currentATL: Double,
        plannedDailyTSS: [Double]
    ) -> [PMCProjection] {
        var results: [PMCProjection] = []
        var ctl = currentCTL
        var atl = currentATL
        let calendar = Calendar.current
        var date = calendar.startOfDay(for: Date())

        for tss in plannedDailyTSS {
            date = calendar.date(byAdding: .day, value: 1, to: date)!

            ctl = calculateCTL(previousCTL: ctl, todayTSS: tss)
            atl = calculateATL(previousATL: atl, todayTSS: tss)
            let tsb = calculateTSB(ctl: ctl, atl: atl)

            results.append(PMCProjection(
                date: date,
                plannedTSS: tss,
                projectedCTL: ctl,
                projectedATL: atl,
                projectedTSB: tsb
            ))
        }

        return results
    }

    /// Calculate when TSB will reach a target value with no training
    static func daysToTargetTSB(
        currentCTL: Double,
        currentATL: Double,
        targetTSB: Double,
        maxDays: Int = 30
    ) -> Int? {
        var ctl = currentCTL
        var atl = currentATL

        for day in 1...maxDays {
            ctl = calculateCTL(previousCTL: ctl, todayTSS: 0)
            atl = calculateATL(previousATL: atl, todayTSS: 0)
            let tsb = calculateTSB(ctl: ctl, atl: atl)

            if tsb >= targetTSB {
                return day
            }
        }

        return nil
    }

    // MARK: - Training Load Analysis

    /// Calculate Acute:Chronic Workload Ratio (ACWR)
    /// Values 0.8-1.3 are generally considered "safe"
    /// Values >1.5 indicate high injury risk
    static func calculateACWR(ctl: Double, atl: Double) -> Double? {
        guard ctl > 0 else { return nil }
        return atl / ctl
    }

    /// Analyze ACWR for injury risk
    static func analyzeACWR(_ acwr: Double?) -> ACWRStatus {
        guard let ratio = acwr else { return .unknown }

        switch ratio {
        case 0.8...1.3: return .optimal
        case 0.5..<0.8: return .undertraining
        case 1.3..<1.5: return .caution
        case 1.5...: return .highRisk
        default: return .veryLow
        }
    }

    /// Calculate training monotony (standard deviation of weekly TSS)
    /// High monotony (>2.0) with high strain increases injury risk
    static func calculateMonotony(weeklyTSS: [Double]) -> Double? {
        guard weeklyTSS.count >= 7 else { return nil }

        let lastWeek = Array(weeklyTSS.suffix(7))
        let mean = lastWeek.reduce(0, +) / 7
        guard mean > 0 else { return nil }

        let variance = lastWeek.reduce(0) { $0 + pow($1 - mean, 2) } / 7
        let stdDev = sqrt(variance)

        return mean / stdDev
    }

    /// Calculate weekly strain (sum of TSS × monotony)
    static func calculateStrain(weeklyTSS: [Double]) -> Double? {
        guard let monotony = calculateMonotony(weeklyTSS: weeklyTSS) else { return nil }
        let weekSum = weeklyTSS.suffix(7).reduce(0, +)
        return weekSum * monotony
    }

    // MARK: - Recommendations

    /// Get TSB-based training recommendation
    static func trainingRecommendation(tsb: Double) -> TSBRecommendation {
        switch tsb {
        case 25...:
            return TSBRecommendation(
                status: .veryFresh,
                recommendation: "Very fresh - great day for high intensity or racing",
                suggestedTSS: 80...150
            )
        case 10..<25:
            return TSBRecommendation(
                status: .fresh,
                recommendation: "Fresh - good for quality training or competitions",
                suggestedTSS: 60...120
            )
        case -10..<10:
            return TSBRecommendation(
                status: .neutral,
                recommendation: "Balanced - normal training load appropriate",
                suggestedTSS: 40...100
            )
        case -25..<(-10):
            return TSBRecommendation(
                status: .tired,
                recommendation: "Fatigued - consider easier training or rest",
                suggestedTSS: 20...60
            )
        default:
            return TSBRecommendation(
                status: .veryTired,
                recommendation: "Very fatigued - rest day or active recovery only",
                suggestedTSS: 0...30
            )
        }
    }

    /// Calculate suggested TSS to reach target TSB in given days
    static func tssToReachTSB(
        currentCTL: Double,
        currentATL: Double,
        targetTSB: Double,
        days: Int
    ) -> Double {
        // This is a simplification - real calculation would iterate
        // For now, estimate based on current gap
        let currentTSB = currentCTL - currentATL
        let tsbGap = targetTSB - currentTSB

        // ATL decays faster than CTL, so rest increases TSB
        // Each rest day increases TSB by roughly ATL/7 - CTL/42
        let dailyTSBIncrease = currentATL / defaultATLDays - currentCTL / defaultCTLDays

        if tsbGap > 0 {
            // Need to increase TSB - rest more
            return max(0, currentATL * 0.5)  // Reduce training
        } else {
            // Need to decrease TSB - train harder
            return currentCTL * 1.2  // Increase training
        }
    }
}

// MARK: - Data Types

struct PMCDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let tss: Double
    let ctl: Double
    let atl: Double
    let tsb: Double

    var formStatus: String {
        PMCCalculator.trainingRecommendation(tsb: tsb).status.rawValue
    }

    var acwr: Double? {
        PMCCalculator.calculateACWR(ctl: ctl, atl: atl)
    }
}

struct PMCProjection: Identifiable {
    let id = UUID()
    let date: Date
    let plannedTSS: Double
    let projectedCTL: Double
    let projectedATL: Double
    let projectedTSB: Double
}

enum ACWRStatus: String {
    case optimal = "Optimal"
    case undertraining = "Undertraining"
    case caution = "Caution"
    case highRisk = "High Risk"
    case veryLow = "Very Low"
    case unknown = "Unknown"

    var color: String {
        switch self {
        case .optimal: return "green"
        case .undertraining: return "blue"
        case .caution: return "orange"
        case .highRisk: return "red"
        case .veryLow: return "gray"
        case .unknown: return "gray"
        }
    }
}

struct TSBRecommendation {
    let status: TSBStatus
    let recommendation: String
    let suggestedTSS: ClosedRange<Double>
}

enum TSBStatus: String {
    case veryFresh = "Very Fresh"
    case fresh = "Fresh"
    case neutral = "Neutral"
    case tired = "Tired"
    case veryTired = "Very Tired"

    var color: String {
        switch self {
        case .veryFresh: return "green"
        case .fresh: return "teal"
        case .neutral: return "blue"
        case .tired: return "orange"
        case .veryTired: return "red"
        }
    }
}
