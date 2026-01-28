//
//  HealthKitService.swift
//  FitnessApp
//
//  Main HealthKit service acting as a facade for specialized sub-services.
//  This maintains backward compatibility while delegating to focused services:
//  - HealthKitCore: Shared functionality, type definitions, helpers
//  - HealthKitWorkoutService: Workout queries and samples
//  - HealthKitWellnessService: Recovery and wellness metrics
//  - HealthKitProfileService: Profile data (age, height, weight)
//  - HealthKitRouteService: GPS route handling
//

import Foundation
import HealthKit
import Observation
import UIKit
import CoreLocation

@Observable
final class HealthKitService {

    // MARK: - Sub-Services

    private let core = HealthKitCore.shared
    private let workoutService: HealthKitWorkoutService
    private let wellnessService: HealthKitWellnessService
    private let profileService: HealthKitProfileService
    private let routeService: HealthKitRouteService

    // MARK: - Observer Management

    private var observerQueries: [HKObserverQuery] = []

    // MARK: - Authorization State

    var isAuthorized = false
    var authorizationError: Error?

    // MARK: - Data State

    var isLoading = false
    var lastSyncDate: Date?

    // MARK: - Initialization

    init() {
        self.workoutService = HealthKitWorkoutService(core: core)
        self.wellnessService = HealthKitWellnessService(core: core)
        self.profileService = HealthKitProfileService(core: core)
        self.routeService = HealthKitRouteService(core: core)
    }

    // MARK: - Cleanup

    /// Stop all observer queries and release resources.
    func stopAllObservers() {
        for query in observerQueries {
            core.healthStore.stop(query)
        }
        observerQueries.removeAll()
    }

    deinit {
        for query in observerQueries {
            core.healthStore.stop(query)
        }
    }

    // MARK: - Simulator Detection

    static var isRunningOnSimulator: Bool {
        HealthKitCore.isRunningOnSimulator
    }

    // MARK: - Type Definitions (Delegated)

    var allReadTypes: Set<HKSampleType> { core.allReadTypes }
    var characteristicTypes: Set<HKCharacteristicType> { core.characteristicTypes }

    // MARK: - Authorization

    var hasAttemptedAuthorization: Bool {
        get { UserDefaults.standard.bool(forKey: "hasAttemptedHealthKitAuth") }
        set { UserDefaults.standard.set(newValue, forKey: "hasAttemptedHealthKitAuth") }
    }

    func requestAuthorization() async {
        print("[HealthKit] Device: \(Self.isRunningOnSimulator ? "Simulator" : "Physical")")
        print("[HealthKit] isHealthDataAvailable: \(HKHealthStore.isHealthDataAvailable())")

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

        await MainActor.run {
            hasAttemptedAuthorization = true
        }

        print("[HealthKit] Starting authorization request...")
        print("[HealthKit] Requesting \(allReadTypes.count) read types")

        do {
            try await core.healthStore.requestAuthorization(
                toShare: [],
                read: Set(allReadTypes.map { $0 as HKObjectType }).union(characteristicTypes)
            )

            print("[HealthKit] Authorization completed successfully")

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

    func openHealthAppSettings() {
        if let url = URL(string: "x-apple-health://") {
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }
    }

    func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            Task { @MainActor in
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Background Observers

    private func startBackgroundObservers() async {
        let workoutType = HKWorkoutType.workoutType()
        let workoutQuery = HKObserverQuery(sampleType: workoutType, predicate: nil) { [weak self] _, completionHandler, error in
            if error == nil {
                Task {
                    await self?.handleNewWorkouts()
                }
            }
            completionHandler()
        }

        core.healthStore.execute(workoutQuery)
        observerQueries.append(workoutQuery)

        do {
            try await core.healthStore.enableBackgroundDelivery(for: workoutType, frequency: .immediate)
        } catch {
            print("Failed to enable background delivery: \(error)")
        }
    }

    private func handleNewWorkouts() async {
        await syncIncrementalWorkouts()
    }

    // MARK: - Workout Queries (Delegated to HealthKitWorkoutService)

    func fetchWorkouts(from startDate: Date, to endDate: Date = Date()) async throws -> [HKWorkout] {
        try await workoutService.fetchWorkouts(from: startDate, to: endDate)
    }

    func syncIncrementalWorkouts() async {
        let (added, _) = await workoutService.syncIncrementalWorkouts()
        if !added.isEmpty {
            await processNewWorkouts(added)
        }
        lastSyncDate = Date()
    }

    private func processNewWorkouts(_ workouts: [HKWorkout]) async {
        print("Processing \(workouts.count) new workouts")
    }

    private func processDeletedWorkouts(_ deletedObjects: [HKDeletedObject]) async {
        print("Processing \(deletedObjects.count) deleted workouts")
    }

    func fetchHeartRateSamples(for workout: HKWorkout) async throws -> [HKQuantitySample] {
        try await workoutService.fetchHeartRateSamples(for: workout)
    }

    func fetchPowerSamples(for workout: HKWorkout, isRunning: Bool) async throws -> [HKQuantitySample] {
        try await workoutService.fetchPowerSamples(for: workout, isRunning: isRunning)
    }

    // MARK: - Wellness Queries (Delegated to HealthKitWellnessService)

    func fetchHRV(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        try await wellnessService.fetchHRV(from: startDate, to: endDate)
    }

    func fetchRestingHeartRate(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        try await wellnessService.fetchRestingHeartRate(from: startDate, to: endDate)
    }

    func fetchSleepAnalysis(for date: Date) async throws -> [HKCategorySample] {
        try await wellnessService.fetchSleepAnalysis(for: date)
    }

    func fetchVO2Max(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        try await wellnessService.fetchVO2Max(from: startDate, to: endDate)
    }

    func fetchHeartRateRecovery(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        try await wellnessService.fetchHeartRateRecovery(from: startDate, to: endDate)
    }

    func fetchLeanBodyMass(from startDate: Date, to endDate: Date = Date()) async throws -> [HKQuantitySample] {
        try await wellnessService.fetchLeanBodyMass(from: startDate, to: endDate)
    }

    func fetchHeartRateEvents(from startDate: Date, to endDate: Date = Date()) async throws -> HeartRateEvents {
        try await wellnessService.fetchHeartRateEvents(from: startDate, to: endDate)
    }

    func calculateVO2MaxTrend(samples: [HKQuantitySample]) -> Trend {
        wellnessService.calculateVO2MaxTrend(samples: samples)
    }

    func fetchSteps(for date: Date) async throws -> Double {
        try await wellnessService.fetchSteps(for: date)
    }

    func fetchActiveCalories(for date: Date) async throws -> Double {
        try await wellnessService.fetchActiveCalories(for: date)
    }

    func parseSleepData(from samples: [HKCategorySample]) -> SleepData {
        wellnessService.parseSleepData(from: samples)
    }

    // MARK: - Profile Queries (Delegated to HealthKitProfileService)

    func fetchDateOfBirth() throws -> Date? {
        try profileService.fetchDateOfBirth()
    }

    func fetchAge() throws -> Int? {
        try profileService.fetchAge()
    }

    func fetchBiologicalSex() throws -> HKBiologicalSex? {
        try profileService.fetchBiologicalSex()
    }

    func fetchHeight() async throws -> Double? {
        try await profileService.fetchHeight()
    }

    func fetchWeight() async throws -> Double? {
        try await profileService.fetchWeight()
    }

    func fetchProfileData() async throws -> HealthProfileData {
        try await profileService.fetchProfileData()
    }

    // MARK: - Route Queries (Delegated to HealthKitRouteService)

    func fetchWorkoutRoute(for workout: HKWorkout) async throws -> [CLLocation] {
        try await routeService.fetchWorkoutRoute(for: workout)
    }

    static func downsampleLocations(_ locations: [CLLocation], maxPoints: Int = 300) -> [CLLocation] {
        HealthKitRouteService.downsampleLocations(locations, maxPoints: maxPoints)
    }

    // MARK: - Historical Backfill

    func performHistoricalBackfill(months: Int = 12) async throws {
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .month, value: -months, to: Date())!

        let workouts = try await fetchWorkouts(from: startDate)
        print("Found \(workouts.count) workouts in backfill")

        for workout in workouts {
            await processNewWorkouts([workout])
        }

        lastSyncDate = Date()
    }
}
