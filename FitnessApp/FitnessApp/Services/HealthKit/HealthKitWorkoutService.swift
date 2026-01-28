//
//  HealthKitWorkoutService.swift
//  FitnessApp
//
//  Handles workout-related HealthKit queries: fetching workouts,
//  heart rate samples, power samples, and incremental sync.
//

import Foundation
import HealthKit

/// Service for fetching workout data from HealthKit.
final class HealthKitWorkoutService {

    private let core: HealthKitCore
    private var anchorsByType: [HKSampleType: HKQueryAnchor] = [:]

    init(core: HealthKitCore = .shared) {
        self.core = core
    }

    // MARK: - Workout Queries

    /// Fetch all workouts within a date range
    func fetchWorkouts(from startDate: Date, to endDate: Date = Date()) async throws -> [HKWorkout] {
        let predicate = core.dateRangePredicate(from: startDate, to: endDate)

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

            core.healthStore.execute(query)
        }
    }

    /// Fetch workouts using anchored query for incremental sync
    /// - Returns: Tuple of (new workouts, deleted workout UUIDs)
    func syncIncrementalWorkouts() async -> (added: [HKWorkout], deleted: [UUID]) {
        let workoutType = HKWorkoutType.workoutType()
        let anchor = anchorsByType[workoutType]

        return await withCheckedContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: workoutType,
                predicate: nil,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { [weak self] _, samples, deletedObjects, newAnchor, _ in
                if let newAnchor {
                    self?.anchorsByType[workoutType] = newAnchor
                }

                let addedWorkouts = (samples as? [HKWorkout]) ?? []
                let deletedUUIDs = deletedObjects?.map { $0.uuid } ?? []

                continuation.resume(returning: (addedWorkouts, deletedUUIDs))
            }

            core.healthStore.execute(query)
        }
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

        return try await core.fetchQuantitySamples(type: hrType, predicate: predicate)
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

        return try await core.fetchQuantitySamples(type: powerType, predicate: predicate)
    }

    /// Fetch cadence samples during a workout
    func fetchCadenceSamples(for workout: HKWorkout, isCycling: Bool) async throws -> [HKQuantitySample] {
        let identifier: HKQuantityTypeIdentifier = isCycling ? .cyclingCadence : .runningStrideLength
        guard let cadenceType = HKQuantityType.quantityType(forIdentifier: identifier) else {
            throw HealthKitError.typeNotAvailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: workout.startDate,
            end: workout.endDate,
            options: .strictStartDate
        )

        return try await core.fetchQuantitySamples(type: cadenceType, predicate: predicate)
    }

    // MARK: - Workout Statistics

    /// Get statistics for a specific metric during a workout
    func workoutStatistics(
        for workout: HKWorkout,
        type: HKQuantityTypeIdentifier
    ) -> HKQuantity? {
        guard let quantityType = HKQuantityType.quantityType(forIdentifier: type) else {
            return nil
        }
        return workout.statistics(for: quantityType)?.averageQuantity()
    }

    /// Get total distance for a workout
    func totalDistance(for workout: HKWorkout) -> Double? {
        workout.totalDistance?.doubleValue(for: .meter())
    }

    /// Get total energy burned for a workout
    func totalEnergyBurned(for workout: HKWorkout) -> Double? {
        workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
    }
}
