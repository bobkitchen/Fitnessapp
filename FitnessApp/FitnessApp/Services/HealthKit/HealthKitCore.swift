//
//  HealthKitCore.swift
//  FitnessApp
//
//  Core HealthKit functionality shared across all HealthKit services.
//  Contains the shared health store, type definitions, and unit conversions.
//

import Foundation
import HealthKit

/// Shared HealthKit core providing common functionality for all HealthKit services.
/// This is a singleton to ensure all services use the same HKHealthStore instance.
final class HealthKitCore {

    /// Shared singleton instance
    static let shared = HealthKitCore()

    /// The shared HealthKit store used by all services
    let healthStore = HKHealthStore()

    private init() {}

    // MARK: - Simulator Detection

    static var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - HealthKit Type Definitions

    /// All workout data types we need to read
    var workoutReadTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKWorkoutType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .heartRate,
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
            .runningPower,
            .cyclingPower,
            .cyclingCadence,
            .runningStrideLength,
            .runningVerticalOscillation,
            .runningGroundContactTime,
            .swimmingStrokeCount
        ]

        for identifier in quantityTypes {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        return types
    }

    /// Recovery and wellness data types
    var wellnessReadTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []

        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .respiratoryRate,
            .oxygenSaturation,
            .bodyTemperature,
            .vo2Max,
            .heartRateRecoveryOneMinute,
            .leanBodyMass
        ]

        for identifier in quantityTypes {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        let categoryTypes: [HKCategoryTypeIdentifier] = [
            .mindfulSession,
            .irregularHeartRhythmEvent,
            .highHeartRateEvent,
            .lowHeartRateEvent
        ]

        for identifier in categoryTypes {
            if let type = HKCategoryType.categoryType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        return types
    }

    /// Body and activity metrics
    var activityReadTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []

        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .stepCount,
            .flightsClimbed,
            .appleExerciseTime,
            .appleMoveTime,
            .appleStandTime,
            .activeEnergyBurned,
            .basalEnergyBurned,
            .bodyMass,
            .height,
            .bodyFatPercentage,
            .bodyMassIndex,
            .walkingSpeed,
            .walkingStepLength
        ]

        for identifier in quantityTypes {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        return types
    }

    /// All types we need to read
    var allReadTypes: Set<HKSampleType> {
        workoutReadTypes.union(wellnessReadTypes).union(activityReadTypes)
    }

    /// Characteristic types (date of birth, biological sex)
    var characteristicTypes: Set<HKCharacteristicType> {
        var types: Set<HKCharacteristicType> = []
        if let dob = HKCharacteristicType.characteristicType(forIdentifier: .dateOfBirth) {
            types.insert(dob)
        }
        if let sex = HKCharacteristicType.characteristicType(forIdentifier: .biologicalSex) {
            types.insert(sex)
        }
        return types
    }

    // MARK: - Unit Conversions

    /// Get the appropriate HKUnit for a given quantity type
    func unit(for type: HKQuantityType) -> HKUnit {
        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue,
             HKQuantityTypeIdentifier.restingHeartRate.rawValue,
             HKQuantityTypeIdentifier.heartRateRecoveryOneMinute.rawValue:
            return HKUnit.count().unitDivided(by: .minute())

        case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue,
             HKQuantityTypeIdentifier.basalEnergyBurned.rawValue:
            return .kilocalorie()

        case HKQuantityTypeIdentifier.stepCount.rawValue,
             HKQuantityTypeIdentifier.flightsClimbed.rawValue:
            return .count()

        case HKQuantityTypeIdentifier.distanceWalkingRunning.rawValue,
             HKQuantityTypeIdentifier.distanceCycling.rawValue,
             HKQuantityTypeIdentifier.distanceSwimming.rawValue:
            return .meter()

        case HKQuantityTypeIdentifier.runningPower.rawValue,
             HKQuantityTypeIdentifier.cyclingPower.rawValue:
            return .watt()

        case HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue:
            return .secondUnit(with: .milli)

        case HKQuantityTypeIdentifier.vo2Max.rawValue:
            return HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo).unitMultiplied(by: .minute()))

        case HKQuantityTypeIdentifier.bodyMass.rawValue,
             HKQuantityTypeIdentifier.leanBodyMass.rawValue:
            return .gramUnit(with: .kilo)

        case HKQuantityTypeIdentifier.bodyFatPercentage.rawValue:
            return .percent()

        case HKQuantityTypeIdentifier.height.rawValue:
            return .meterUnit(with: .centi)

        default:
            return .count()
        }
    }

    // MARK: - Common Query Helpers

    /// Fetch quantity samples with a predicate
    func fetchQuantitySamples(
        type: HKQuantityType,
        predicate: NSPredicate,
        ascending: Bool = true
    ) async throws -> [HKQuantitySample] {
        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: ascending
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let quantitySamples = samples as? [HKQuantitySample] ?? []
                continuation.resume(returning: quantitySamples)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch category samples with a predicate
    func fetchCategorySamples(
        type: HKCategoryType,
        from startDate: Date,
        to endDate: Date
    ) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let categorySamples = samples as? [HKCategorySample] ?? []
                continuation.resume(returning: categorySamples)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch statistics for a quantity type
    func fetchStatistics(
        type: HKQuantityType,
        start: Date,
        end: Date,
        option: HKStatisticsOptions
    ) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: option
            ) { [self] _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value: Double
                if option == .cumulativeSum {
                    value = statistics?.sumQuantity()?.doubleValue(for: unit(for: type)) ?? 0
                } else {
                    value = statistics?.averageQuantity()?.doubleValue(for: unit(for: type)) ?? 0
                }
                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }

    /// Create a date range predicate
    func dateRangePredicate(from startDate: Date, to endDate: Date) -> NSPredicate {
        HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )
    }
}

// MARK: - HealthKit Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case typeNotAvailable
    case authorizationDenied
    case queryFailed(Error)
    case simulatorNotSupported
    case authorizationTimeout

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .typeNotAvailable:
            return "The requested health data type is not available"
        case .authorizationDenied:
            return "Authorization to access health data was denied"
        case .queryFailed(let error):
            return "Query failed: \(error.localizedDescription)"
        case .simulatorNotSupported:
            return "HealthKit authorization requires a physical iPhone. The Simulator does not support HealthKit permission dialogs."
        case .authorizationTimeout:
            return "Authorization request timed out. Try tapping 'Open Health App' to enable permissions manually."
        }
    }
}
