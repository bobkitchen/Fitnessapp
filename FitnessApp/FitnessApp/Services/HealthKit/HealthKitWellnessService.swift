//
//  HealthKitWellnessService.swift
//  FitnessApp
//
//  Handles wellness and recovery metrics from HealthKit: HRV, resting HR,
//  sleep analysis, VO2 Max, heart rate recovery, and cardiac events.
//

import Foundation
import HealthKit

/// Service for fetching wellness and recovery data from HealthKit.
final class HealthKitWellnessService {

    private let core: HealthKitCore

    init(core: HealthKitCore = .shared) {
        self.core = core
    }

    // MARK: - HRV

    /// Fetch HRV data for a date range
    func fetchHRV(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = core.dateRangePredicate(from: startDate, to: endDate)
        return try await core.fetchQuantitySamples(type: hrvType, predicate: predicate)
    }

    /// Get most recent HRV value
    func fetchLatestHRV() async throws -> Double? {
        let samples = try await fetchHRV(
            from: Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        )
        guard let latest = samples.last else { return nil }
        return latest.quantity.doubleValue(for: .secondUnit(with: .milli))
    }

    // MARK: - Resting Heart Rate

    /// Fetch resting heart rate for a date range
    func fetchRestingHeartRate(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        guard let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = core.dateRangePredicate(from: startDate, to: endDate)
        return try await core.fetchQuantitySamples(type: rhrType, predicate: predicate)
    }

    /// Get most recent resting heart rate
    func fetchLatestRestingHeartRate() async throws -> Int? {
        let samples = try await fetchRestingHeartRate(
            from: Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        )
        guard let latest = samples.last else { return nil }
        let unit = HKUnit.count().unitDivided(by: .minute())
        return Int(latest.quantity.doubleValue(for: unit))
    }

    // MARK: - Sleep Analysis

    /// Fetch sleep analysis for a date
    func fetchSleepAnalysis(for date: Date) async throws -> [HKCategorySample] {
        guard let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitError.typeNotAvailable
        }

        // Get sleep for the night before the given date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let previousEvening = calendar.date(byAdding: .hour, value: -12, to: startOfDay)!
        let nextMorning = calendar.date(byAdding: .hour, value: 12, to: startOfDay)!

        return try await core.fetchCategorySamples(
            type: sleepType,
            from: previousEvening,
            to: nextMorning
        )
    }

    /// Parse sleep samples into structured sleep data
    func parseSleepData(from samples: [HKCategorySample]) -> SleepData {
        var totalAsleep: TimeInterval = 0
        var deepSleep: TimeInterval = 0
        var remSleep: TimeInterval = 0
        var coreSleep: TimeInterval = 0
        var awakeTime: TimeInterval = 0
        var timeInBed: TimeInterval = 0

        var earliestStart: Date?
        var latestEnd: Date?

        for sample in samples {
            let duration = sample.endDate.timeIntervalSince(sample.startDate)

            if earliestStart == nil || sample.startDate < earliestStart! {
                earliestStart = sample.startDate
            }
            if latestEnd == nil || sample.endDate > latestEnd! {
                latestEnd = sample.endDate
            }

            switch sample.value {
            case HKCategoryValueSleepAnalysis.inBed.rawValue:
                timeInBed += duration
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                 HKCategoryValueSleepAnalysis.asleepCore.rawValue:
                coreSleep += duration
                totalAsleep += duration
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                deepSleep += duration
                totalAsleep += duration
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                remSleep += duration
                totalAsleep += duration
            case HKCategoryValueSleepAnalysis.awake.rawValue:
                awakeTime += duration
            default:
                break
            }
        }

        // If no in-bed data, use the span of all samples
        if timeInBed == 0, let start = earliestStart, let end = latestEnd {
            timeInBed = end.timeIntervalSince(start)
        }

        let efficiency = timeInBed > 0 ? totalAsleep / timeInBed : 0

        return SleepData(
            totalSleepHours: totalAsleep / 3600,
            deepSleepMinutes: deepSleep / 60,
            remSleepMinutes: remSleep / 60,
            coreSleepMinutes: coreSleep / 60,
            awakeMinutes: awakeTime / 60,
            efficiency: efficiency,
            startTime: earliestStart,
            endTime: latestEnd
        )
    }

    // MARK: - VO2 Max

    /// Fetch VO2max values
    func fetchVO2Max(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        guard let vo2Type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = core.dateRangePredicate(from: startDate, to: endDate)
        return try await core.fetchQuantitySamples(type: vo2Type, predicate: predicate)
    }

    /// Calculate VO2 Max trend over recent samples
    func calculateVO2MaxTrend(samples: [HKQuantitySample]) -> Trend {
        guard samples.count >= 2 else { return .stable }

        let sortedSamples = samples.sorted { $0.startDate < $1.startDate }
        let unit = HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute()))

        let midpoint = sortedSamples.count / 2
        let firstHalf = sortedSamples.prefix(midpoint).map { $0.quantity.doubleValue(for: unit) }
        let secondHalf = sortedSamples.suffix(sortedSamples.count - midpoint).map { $0.quantity.doubleValue(for: unit) }

        let firstAvg = firstHalf.reduce(0, +) / Double(firstHalf.count)
        let secondAvg = secondHalf.reduce(0, +) / Double(secondHalf.count)

        let percentChange = (secondAvg - firstAvg) / firstAvg * 100

        if percentChange > 2 {
            return .up
        } else if percentChange < -2 {
            return .down
        } else {
            return .stable
        }
    }

    // MARK: - Heart Rate Recovery

    /// Fetch heart rate recovery (1-minute post-workout drop) samples
    func fetchHeartRateRecovery(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        guard let hrrType = HKQuantityType.quantityType(forIdentifier: .heartRateRecoveryOneMinute) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = core.dateRangePredicate(from: startDate, to: endDate)
        return try await core.fetchQuantitySamples(type: hrrType, predicate: predicate)
    }

    // MARK: - Body Composition

    /// Fetch lean body mass measurements
    func fetchLeanBodyMass(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        guard let lbmType = HKQuantityType.quantityType(forIdentifier: .leanBodyMass) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = core.dateRangePredicate(from: startDate, to: endDate)
        return try await core.fetchQuantitySamples(type: lbmType, predicate: predicate)
    }

    // MARK: - Cardiac Events

    /// Fetch cardiac events (irregular rhythm, high HR, low HR)
    func fetchHeartRateEvents(from startDate: Date, to endDate: Date = Date()) async throws -> HeartRateEvents {
        var events = HeartRateEvents()

        if let irregularType = HKCategoryType.categoryType(forIdentifier: .irregularHeartRhythmEvent) {
            let samples = try await core.fetchCategorySamples(type: irregularType, from: startDate, to: endDate)
            events.irregularRhythmCount = samples.count
        }

        if let highHRType = HKCategoryType.categoryType(forIdentifier: .highHeartRateEvent) {
            let samples = try await core.fetchCategorySamples(type: highHRType, from: startDate, to: endDate)
            events.highHeartRateCount = samples.count
        }

        if let lowHRType = HKCategoryType.categoryType(forIdentifier: .lowHeartRateEvent) {
            let samples = try await core.fetchCategorySamples(type: lowHRType, from: startDate, to: endDate)
            events.lowHeartRateCount = samples.count
        }

        return events
    }

    // MARK: - Activity Metrics

    /// Fetch step count for a date
    func fetchSteps(for date: Date) async throws -> Double {
        guard let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.typeNotAvailable
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await core.fetchStatistics(type: stepsType, start: startOfDay, end: endOfDay, option: .cumulativeSum)
    }

    /// Fetch active calories for a date
    func fetchActiveCalories(for date: Date) async throws -> Double {
        guard let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.typeNotAvailable
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await core.fetchStatistics(type: caloriesType, start: startOfDay, end: endOfDay, option: .cumulativeSum)
    }
}

// MARK: - Data Structures

/// Structured sleep data
struct SleepData {
    let totalSleepHours: Double
    let deepSleepMinutes: Double
    let remSleepMinutes: Double
    let coreSleepMinutes: Double
    let awakeMinutes: Double
    let efficiency: Double  // 0-1
    let startTime: Date?
    let endTime: Date?

    var qualityScore: Double {
        var score = 0.0
        var factors = 0

        // Duration (7-9 hours ideal)
        let durationScore: Double
        switch totalSleepHours {
        case 7...9: durationScore = 1.0
        case 6..<7, 9..<10: durationScore = 0.7
        default: durationScore = 0.4
        }
        score += durationScore
        factors += 1

        // Efficiency (>90% ideal)
        let efficiencyScore = min(efficiency / 0.9, 1.0)
        score += efficiencyScore
        factors += 1

        // Deep sleep (15-20% of total is ideal)
        let totalMinutes = totalSleepHours * 60
        if totalMinutes > 0 {
            let deepPercent = deepSleepMinutes / totalMinutes
            let deepScore: Double
            switch deepPercent {
            case 0.15...0.25: deepScore = 1.0
            case 0.10..<0.15, 0.25..<0.30: deepScore = 0.7
            default: deepScore = 0.4
            }
            score += deepScore
            factors += 1
        }

        return factors > 0 ? score / Double(factors) : 0.5
    }
}

/// Cardiac events from HealthKit
struct HeartRateEvents {
    var irregularRhythmCount: Int = 0
    var highHeartRateCount: Int = 0
    var lowHeartRateCount: Int = 0

    var totalCount: Int {
        irregularRhythmCount + highHeartRateCount + lowHeartRateCount
    }

    var hasAnyEvents: Bool {
        totalCount > 0
    }

    var status: String {
        if irregularRhythmCount > 0 {
            return "Review Recommended"
        } else if highHeartRateCount > 5 || lowHeartRateCount > 5 {
            return "Elevated Activity"
        } else if totalCount > 0 {
            return "Minor Activity"
        }
        return "Normal"
    }
}
