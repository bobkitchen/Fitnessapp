import Foundation
import HealthKit
import Observation
import UIKit

@Observable
final class HealthKitService {
    private let healthStore = HKHealthStore()
    private var observerQueries: [HKObserverQuery] = []
    private var anchorsByType: [HKSampleType: HKQueryAnchor] = [:]

    // MARK: - Authorization State
    var isAuthorized = false
    var authorizationError: Error?

    // MARK: - Simulator Detection
    static var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Data State
    var isLoading = false
    var lastSyncDate: Date?

    // MARK: - HealthKit Types

    /// All workout data types we need to read
    private var workoutReadTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [
            HKWorkoutType.workoutType(),
            HKSeriesType.workoutRoute()
        ]

        // Workout metrics
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
    private var wellnessReadTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = []

        // Sleep
        if let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleepType)
        }

        // Recovery metrics
        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .heartRateVariabilitySDNN,
            .restingHeartRate,
            .respiratoryRate,
            .oxygenSaturation,
            .bodyTemperature,
            .vo2Max
        ]

        for identifier in quantityTypes {
            if let type = HKQuantityType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }

        // Mindfulness
        if let mindfulType = HKCategoryType.categoryType(forIdentifier: .mindfulSession) {
            types.insert(mindfulType)
        }

        return types
    }

    /// Body and activity metrics
    private var activityReadTypes: Set<HKSampleType> {
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

    /// Characteristic types
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

    // MARK: - Authorization

    /// Whether we've attempted authorization before
    var hasAttemptedAuthorization: Bool {
        get { UserDefaults.standard.bool(forKey: "hasAttemptedHealthKitAuth") }
        set { UserDefaults.standard.set(newValue, forKey: "hasAttemptedHealthKitAuth") }
    }

    func requestAuthorization() async {
        print("[HealthKit] Device: \(Self.isRunningOnSimulator ? "Simulator" : "Physical")")
        print("[HealthKit] isHealthDataAvailable: \(HKHealthStore.isHealthDataAvailable())")

        // Check if running on simulator first
        guard !Self.isRunningOnSimulator else {
            print("[HealthKit] Error: Simulator not supported for HealthKit authorization")
            await MainActor.run {
                authorizationError = HealthKitError.simulatorNotSupported
                isAuthorized = false
            }
            return
        }

        guard HKHealthStore.isHealthDataAvailable() else {
            print("[HealthKit] Error: HealthKit not available on this device")
            await MainActor.run {
                authorizationError = HealthKitError.notAvailable
                isAuthorized = false
            }
            return
        }

        // Mark that we've attempted authorization
        await MainActor.run {
            hasAttemptedAuthorization = true
        }

        print("[HealthKit] Starting authorization request...")
        print("[HealthKit] Requesting \(allReadTypes.count) read types")

        do {
            try await healthStore.requestAuthorization(
                toShare: [],  // We're read-only
                read: Set(allReadTypes.map { $0 as HKObjectType }).union(characteristicTypes)
            )

            print("[HealthKit] Authorization completed successfully")

            // After the authorization dialog is dismissed, assume authorized
            // Apple doesn't tell us if read permissions were denied (privacy)
            // We'll find out when we try to fetch data
            await MainActor.run {
                isAuthorized = true
                authorizationError = nil
            }

            await startBackgroundObservers()
        } catch {
            print("[HealthKit] Error: \(error.localizedDescription)")
            await MainActor.run {
                authorizationError = error
                isAuthorized = false
            }
        }
    }

    /// Open the Health app to the data sources page for this app
    func openHealthAppSettings() {
        if let url = URL(string: "x-apple-health://") {
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }
    }

    /// Open iOS Settings app to the app's settings page
    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Background Observers

    private func startBackgroundObservers() async {
        // Observe workouts for real-time sync
        let workoutType = HKWorkoutType.workoutType()
        let workoutQuery = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
            if error == nil {
                Task {
                    await self?.handleNewWorkouts()
                }
            }
            completionHandler()
        }

        healthStore.execute(workoutQuery)
        observerQueries.append(workoutQuery)

        // Enable background delivery
        do {
            try await healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate)
        } catch {
            print("Failed to enable background delivery: \(error)")
        }
    }

    private func handleNewWorkouts() async {
        // This will be called when new workouts are detected
        // Trigger incremental sync
        await syncIncrementalWorkouts()
    }

    // MARK: - Workout Queries

    /// Fetch all workouts within a date range
    func fetchWorkouts(from startDate: Date, to endDate: Date = Date()) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: false
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch workouts using anchored query for incremental sync
    func syncIncrementalWorkouts() async {
        let workoutType = HKWorkoutType.workoutType()
        let anchor = anchorsByType[workoutType]

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let query = HKAnchoredObjectQuery(
                type: workoutType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] query, samples, deletedObjects, newAnchor, error in
                if let newAnchor {
                    self?.anchorsByType[workoutType] = newAnchor
                }

                // Process new workouts
                if let workouts = samples as? [HKWorkout], !workouts.isEmpty {
                    Task {
                        await self?.processNewWorkouts(workouts)
                    }
                }

                // Handle deleted workouts
                if let deleted = deletedObjects, !deleted.isEmpty {
                    Task {
                        await self?.processDeletedWorkouts(deleted)
                    }
                }

                self?.lastSyncDate = Date()
                continuation.resume()
            }

            healthStore.execute(query)
        }
    }

    private func processNewWorkouts(_ workouts: [HKWorkout]) async {
        // Will be implemented to create WorkoutRecord entries
        print("Processing \(workouts.count) new workouts")
    }

    private func processDeletedWorkouts(_ deletedObjects: [HKDeletedObject]) async {
        // Will be implemented to remove deleted workouts
        print("Processing \(deletedObjects.count) deleted workouts")
    }

    // MARK: - Workout Detail Queries

    /// Fetch heart rate samples during a workout
    func fetchHeartRateSamples(for workout: HKWorkout) async throws -> [HKQuantitySample] {
        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        return try await fetchQuantitySamples(type: hrType, predicate: predicate)
    }

    /// Fetch power samples during a workout (cycling or running)
    func fetchPowerSamples(for workout: HKWorkout, isRunning: Bool) async throws -> [HKQuantitySample] {
        let identifier: HKQuantityTypeIdentifier = isRunning ? .runningPower : .cyclingPower
        guard let powerType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        return try await fetchQuantitySamples(type: powerType, predicate: predicate)
    }

    private func fetchQuantitySamples(type: HKQuantityType, predicate: NSPredicate) async throws -> [HKQuantitySample] {
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

                let quantitySamples = samples as? [HKQuantitySample] ?? []
                continuation.resume(returning: quantitySamples)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Recovery Metrics

    /// Fetch HRV data for a date range
    func fetchHRV(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        guard let hrvType = HKQuantityType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await fetchQuantitySamples(type: hrvType, predicate: predicate)
    }

    /// Fetch resting heart rate for a date range
    func fetchRestingHeartRate(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        guard let rhrType = HKQuantityType.quantityType(forIdentifier: .restingHeartRate) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await fetchQuantitySamples(type: rhrType, predicate: predicate)
    }

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

        let predicate = HKQuery.predicateForSamples(
            withStart: previousEvening,
            end: nextMorning,
            options: .strictStartDate
        )

        let sortDescriptor = NSSortDescriptor(
            key: HKSampleSortIdentifierStartDate,
            ascending: true
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let sleepSamples = samples as? [HKCategorySample] ?? []
                continuation.resume(returning: sleepSamples)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch VO2max values
    func fetchVO2Max(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        guard let vo2Type = HKQuantityType.quantityType(forIdentifier: .vo2Max) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: startDate,
            end: endDate,
            options: .strictStartDate
        )

        return try await fetchQuantitySamples(type: vo2Type, predicate: predicate)
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

        return try await fetchStatistics(type: stepsType, start: startOfDay, end: endOfDay, option: .cumulativeSum)
    }

    /// Fetch active calories for a date
    func fetchActiveCalories(for date: Date) async throws -> Double {
        guard let caloriesType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.typeNotAvailable
        }

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        return try await fetchStatistics(type: caloriesType, start: startOfDay, end: endOfDay, option: .cumulativeSum)
    }

    // MARK: - Profile Data (Age, Height, Weight)

    /// Fetch date of birth from HealthKit characteristics
    func fetchDateOfBirth() throws -> Date? {
        let dobComponents = try healthStore.dateOfBirthComponents()
        return Calendar.current.date(from: dobComponents)
    }

    /// Calculate age from date of birth
    func fetchAge() throws -> Int? {
        guard let dob = try fetchDateOfBirth() else { return nil }
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dob, to: Date())
        return ageComponents.year
    }

    /// Fetch biological sex from HealthKit characteristics
    func fetchBiologicalSex() throws -> HKBiologicalSex? {
        let biologicalSex = try healthStore.biologicalSex()
        return biologicalSex.biologicalSex
    }

    /// Fetch most recent height measurement (in cm)
    func fetchHeight() async throws -> Double? {
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else {
            throw HealthKitError.typeNotAvailable
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let heightCm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                continuation.resume(returning: heightCm)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch most recent weight measurement (in kg)
    func fetchWeight() async throws -> Double? {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitError.typeNotAvailable
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let weightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: weightKg)
            }

            healthStore.execute(query)
        }
    }

    /// Fetch all profile data at once
    func fetchProfileData() async throws -> HealthProfileData {
        // Fetch characteristics (sync)
        let age = try? fetchAge()
        let biologicalSex = try? fetchBiologicalSex()

        // Fetch measurements (async)
        let height = try? await fetchHeight()
        let weight = try? await fetchWeight()

        return HealthProfileData(
            age: age,
            biologicalSex: biologicalSex,
            heightCm: height,
            weightKg: weight
        )
    }

    private func fetchStatistics(type: HKQuantityType, start: Date, end: Date, option: HKStatisticsOptions) async throws -> Double {
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
            ) { _, statistics, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let value: Double
                if option == .cumulativeSum {
                    value = statistics?.sumQuantity()?.doubleValue(for: self.unit(for: type)) ?? 0
                } else {
                    value = statistics?.averageQuantity()?.doubleValue(for: self.unit(for: type)) ?? 0
                }
                continuation.resume(returning: value)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Helper Methods

    private func unit(for type: HKQuantityType) -> HKUnit {
        switch type.identifier {
        case HKQuantityTypeIdentifier.heartRate.rawValue,
             HKQuantityTypeIdentifier.restingHeartRate.rawValue:
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

        case HKQuantityTypeIdentifier.bodyMass.rawValue:
            return .gramUnit(with: .kilo)

        case HKQuantityTypeIdentifier.bodyFatPercentage.rawValue:
            return .percent()

        default:
            return .count()
        }
    }

    /// Historical backfill - fetch all data from a start date
    func performHistoricalBackfill(months: Int = 12) async throws {
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .month, value: -months, to: Date())!

        // Fetch all workouts
        let workouts = try await fetchWorkouts(from: startDate)
        print("Found \(workouts.count) workouts in backfill")

        // Process each workout
        for workout in workouts {
            await processNewWorkouts([workout])
        }

        lastSyncDate = Date()
    }
}

// MARK: - Errors

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

// MARK: - Sleep Analysis Helpers

extension HealthKitService {
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
}

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

/// Profile data fetched from HealthKit
struct HealthProfileData {
    let age: Int?
    let biologicalSex: HKBiologicalSex?
    let heightCm: Double?
    let weightKg: Double?

    var sexString: String? {
        switch biologicalSex {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        default: return nil
        }
    }
}
