import Foundation
import HealthKit
import SwiftData
import Observation

/// Service that syncs HealthKit data to SwiftData
@Observable
@MainActor
final class WorkoutSyncService {
    private let healthKitService: HealthKitService

    // Sync state
    var isSyncing = false
    var lastSyncDate: Date?
    var syncError: Error?

    // Progress tracking
    var syncProgress: SyncProgress = SyncProgress()

    // Statistics (persisted)
    var syncStatistics: SyncStatistics {
        get { loadStatistics() }
        set { saveStatistics(newValue) }
    }

    // TSS Scaling profile (loaded during sync)
    private var scalingProfile: TSSScalingProfile?

    init(healthKitService: HealthKitService) {
        self.healthKitService = healthKitService
    }

    // MARK: - Statistics Persistence

    private func loadStatistics() -> SyncStatistics {
        guard let data = UserDefaults.standard.data(forKey: "syncStatistics"),
              let stats = try? JSONDecoder().decode(SyncStatistics.self, from: data) else {
            return SyncStatistics()
        }
        return stats
    }

    private func saveStatistics(_ stats: SyncStatistics) {
        if let data = try? JSONEncoder().encode(stats) {
            UserDefaults.standard.set(data, forKey: "syncStatistics")
        }
    }

    // MARK: - TSS Scaling

    /// Load the TSS scaling profile from the model context
    private func loadScalingProfile(from modelContext: ModelContext) {
        let descriptor = FetchDescriptor<TSSScalingProfile>()
        scalingProfile = try? modelContext.fetch(descriptor).first

        if let profile = scalingProfile, profile.canApplyScaling {
            print("WorkoutSyncService: Loaded TSS scaling profile - factor=\(String(format: "%.3f", profile.globalScalingFactor)) confidence=\(String(format: "%.0f%%", profile.globalConfidence * 100))")
        }
    }

    // MARK: - Main Sync Methods

    /// Perform initial historical sync (12 months)
    func performInitialSync(modelContext: ModelContext, profile: AthleteProfile?) async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil
        syncProgress = SyncProgress()

        defer {
            isSyncing = false
            syncProgress.phase = .complete
        }

        do {
            // Load TSS scaling profile if available
            loadScalingProfile(from: modelContext)

            let calendar = Calendar.current
            let startDate = calendar.date(byAdding: .month, value: -12, to: Date())!

            // Fetch workouts from HealthKit
            syncProgress.phase = .fetchingWorkouts
            let workouts = try await healthKitService.fetchWorkouts(from: startDate)
            syncProgress.totalWorkouts = workouts.count
            print("WorkoutSyncService: Found \(workouts.count) workouts to sync")

            // Process workouts in batches to avoid timeouts
            syncProgress.phase = .processingWorkouts
            let batchSize = 50
            for batchStart in stride(from: 0, to: workouts.count, by: batchSize) {
                let batchEnd = min(batchStart + batchSize, workouts.count)
                let batch = Array(workouts[batchStart..<batchEnd])

                for workout in batch {
                    let result = await processAndSaveWorkout(workout, modelContext: modelContext, profile: profile)
                    if result.wasInserted {
                        syncProgress.processedWorkouts += 1
                        syncProgress.workoutsByType[result.category, default: 0] += 1
                        syncProgress.workoutsByTSSType[result.tssType, default: 0] += 1
                    }
                }

                // Save batch and yield to prevent UI freezes
                try modelContext.save()
                print("WorkoutSyncService: Processed batch \(batchStart/batchSize + 1), total: \(syncProgress.processedWorkouts) workouts")

                // Brief yield to allow UI updates
                await Task.yield()
            }

            // Update PMC metrics for all days
            syncProgress.phase = .calculatingPMC
            await recalculatePMC(modelContext: modelContext, from: startDate)

            // Sync wellness data (last 30 days only for initial sync to save time)
            syncProgress.phase = .syncingWellness
            let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date())!
            await syncWellnessData(modelContext: modelContext, from: thirtyDaysAgo)

            try modelContext.save()
            lastSyncDate = Date()

            // Update persisted statistics
            var stats = syncStatistics
            stats.totalSyncs += 1
            stats.lastSyncDate = Date()
            stats.lastSyncWorkoutCount = syncProgress.processedWorkouts
            stats.totalWorkoutsSynced += syncProgress.processedWorkouts
            syncStatistics = stats

            print("WorkoutSyncService: Sync complete. Processed \(syncProgress.processedWorkouts) workouts")
        } catch {
            print("WorkoutSyncService: Sync failed - \(error)")
            syncError = error
        }
    }

    /// Incremental sync for new workouts
    func performIncrementalSync(modelContext: ModelContext, profile: AthleteProfile?) async {
        guard !isSyncing else { return }
        isSyncing = true
        syncError = nil

        defer { isSyncing = false }

        do {
            // Load TSS scaling profile if available
            loadScalingProfile(from: modelContext)

            // Get the date of the last synced workout
            let descriptor = FetchDescriptor<WorkoutRecord>(
                sortBy: [SortDescriptor(\.startDate, order: .reverse)]
            )
            let existingWorkouts = try modelContext.fetch(descriptor)
            let lastSyncedDate = existingWorkouts.first?.startDate ?? Calendar.current.date(byAdding: .day, value: -7, to: Date())!

            // Fetch new workouts since last sync
            let newWorkouts = try await healthKitService.fetchWorkouts(from: lastSyncedDate)

            // Filter out already synced workouts
            let existingUUIDs = Set(existingWorkouts.compactMap { $0.healthKitUUID })
            let workoutsToSync = newWorkouts.filter { !existingUUIDs.contains($0.uuid) }

            print("WorkoutSyncService: Found \(workoutsToSync.count) new workouts")

            for workout in workoutsToSync {
                _ = await processAndSaveWorkout(workout, modelContext: modelContext, profile: profile)
            }

            // Update PMC for affected days
            if let earliestNew = workoutsToSync.map({ $0.startDate }).min() {
                await recalculatePMC(modelContext: modelContext, from: earliestNew)
            }

            // Sync today's wellness data
            await syncWellnessData(modelContext: modelContext, from: Calendar.current.startOfDay(for: Date()))

            try modelContext.save()
            lastSyncDate = Date()
        } catch {
            print("WorkoutSyncService: Incremental sync failed - \(error)")
            syncError = error
        }
    }

    // MARK: - Workout Processing

    @discardableResult
    private func processAndSaveWorkout(_ hkWorkout: HKWorkout, modelContext: ModelContext, profile: AthleteProfile?) async -> WorkoutProcessResult {
        // Determine activity type and category
        let activityType = workoutActivityName(hkWorkout.workoutActivityType)
        let category = activityCategory(for: hkWorkout.workoutActivityType)

        // Check if already exists
        let uuid = hkWorkout.uuid
        let predicate = #Predicate<WorkoutRecord> { $0.healthKitUUID == uuid }
        let descriptor = FetchDescriptor<WorkoutRecord>(predicate: predicate)

        do {
            let existing = try modelContext.fetch(descriptor)
            if !existing.isEmpty {
                return WorkoutProcessResult(wasInserted: false, category: category, tssType: .estimated)
            }
        } catch {
            print("Error checking for existing workout: \(error)")
        }

        // Calculate TSS
        let tssResult = await calculateTSS(for: hkWorkout, category: category, profile: profile)

        // Create WorkoutRecord
        let workoutRecord = WorkoutRecord(
            healthKitUUID: uuid,
            activityType: activityType,
            activityCategory: category,
            startDate: hkWorkout.startDate,
            endDate: hkWorkout.endDate,
            durationSeconds: hkWorkout.duration,
            distanceMeters: hkWorkout.totalDistance?.doubleValue(for: .meter()),
            tss: tssResult.tss,
            tssType: tssResult.type,
            intensityFactor: tssResult.intensityFactor
        )

        // Set optional properties
        workoutRecord.normalizedPower = tssResult.normalizedPower
        workoutRecord.normalizedPace = tssResult.normalizedPace
        workoutRecord.averageHeartRate = tssResult.averageHeartRate
        workoutRecord.title = hkWorkout.metadata?[HKMetadataKeyWorkoutBrandName] as? String

        modelContext.insert(workoutRecord)
        return WorkoutProcessResult(wasInserted: true, category: category, tssType: tssResult.type)
    }

    private func calculateTSS(for workout: HKWorkout, category: ActivityCategory, profile: AthleteProfile?) async -> TSSResult {
        let duration = workout.duration

        // Try power-based TSS first
        if category == .bike || category == .run {
            do {
                let powerSamples = try await healthKitService.fetchPowerSamples(for: workout, isRunning: category == .run)

                if !powerSamples.isEmpty {
                    // Use the HKQuantitySample version which properly resamples to 1-second intervals
                    // This is critical for accurate NP calculation
                    if let np = NormalizedPowerCalculator.calculateNormalizedPower(from: powerSamples) {
                        let threshold: Int
                        if category == .bike {
                            threshold = profile?.ftpWatts ?? 200
                        } else {
                            threshold = profile?.runningFTPWatts ?? 250
                        }

                        var tssResult = TSSCalculator.calculatePowerTSS(
                            normalizedPower: np,
                            durationSeconds: duration,
                            ftp: threshold
                        )

                        // Apply TSS scaling if available
                        applyTSSScaling(to: &tssResult, category: category)

                        // Fetch and add average HR
                        if let avgHR = await fetchAverageHeartRate(for: workout) {
                            tssResult.averageHeartRate = avgHR
                        }

                        let scalingNote = tssResult.scalingApplied ? " (scaled from \(String(format: "%.0f", tssResult.originalTSS ?? 0)))" : ""
                        print("WorkoutSyncService: Power TSS - NP=\(np)W, IF=\(String(format: "%.2f", tssResult.intensityFactor)), TSS=\(String(format: "%.0f", tssResult.tss))\(scalingNote)")
                        return tssResult
                    }
                }
            } catch {
                print("Failed to fetch power data: \(error)")
            }
        }

        // Fall back to HR-based TSS
        do {
            let hrSamples = try await healthKitService.fetchHeartRateSamples(for: workout)

            if !hrSamples.isEmpty {
                let hrValues = hrSamples.map { Int($0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) }
                let avgHR = hrValues.reduce(0, +) / hrValues.count

                let thresholdHR = profile?.thresholdHeartRate ?? 165

                var result = TSSCalculator.calculateHeartRateTSS(
                    averageHR: avgHR,
                    durationSeconds: duration,
                    thresholdHR: thresholdHR
                )

                // Apply TSS scaling if available
                applyTSSScaling(to: &result, category: category)

                let scalingNote = result.scalingApplied ? " (scaled from \(String(format: "%.0f", result.originalTSS ?? 0)))" : ""
                print("WorkoutSyncService: HR TSS fallback - avgHR=\(avgHR), LTHR=\(thresholdHR), TSS=\(String(format: "%.0f", result.tss))\(scalingNote)")
                return result
            }
        } catch {
            print("Failed to fetch HR data: \(error)")
        }

        // Last resort: estimate from duration with moderate intensity
        print("WorkoutSyncService: Estimated TSS fallback - duration=\(String(format: "%.0f", duration))s")
        var result = TSSCalculator.estimateTSS(
            durationSeconds: duration,
            perceivedIntensity: 0.5
        )

        // Apply TSS scaling if available
        applyTSSScaling(to: &result, category: category)

        return result
    }

    /// Apply TSS scaling from learned profile
    private func applyTSSScaling(to result: inout TSSResult, category: ActivityCategory) {
        guard let profile = scalingProfile, profile.canApplyScaling else { return }

        let scalingFactor = profile.scalingFactor(for: category)
        result.applyScaling(factor: scalingFactor)
    }

    private func fetchAverageHeartRate(for workout: HKWorkout) async -> Int? {
        do {
            let hrSamples = try await healthKitService.fetchHeartRateSamples(for: workout)
            guard !hrSamples.isEmpty else { return nil }

            let hrValues = hrSamples.map { Int($0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) }
            return hrValues.reduce(0, +) / hrValues.count
        } catch {
            return nil
        }
    }

    // MARK: - PMC Calculation

    private func recalculatePMC(modelContext: ModelContext, from startDate: Date) async {
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())

        // Get or create previous day's metrics for seed values
        var previousCTL: Double = 0
        var previousATL: Double = 0

        // Try to get the day before start date for initial values
        if let dayBefore = calendar.date(byAdding: .day, value: -1, to: currentDate) {
            let predicate = #Predicate<DailyMetrics> { metrics in
                metrics.date >= dayBefore && metrics.date < currentDate
            }
            let descriptor = FetchDescriptor<DailyMetrics>(predicate: predicate)
            if let previousMetrics = try? modelContext.fetch(descriptor).first {
                previousCTL = previousMetrics.ctl
                previousATL = previousMetrics.atl
            }
        }

        // Process each day
        while currentDate <= today {
            let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!

            // Get workouts for this day
            let workoutPredicate = #Predicate<WorkoutRecord> { workout in
                workout.startDate >= currentDate && workout.startDate < nextDate
            }
            let workoutDescriptor = FetchDescriptor<WorkoutRecord>(predicate: workoutPredicate)
            let dayWorkouts = (try? modelContext.fetch(workoutDescriptor)) ?? []

            let dailyTSS = dayWorkouts.reduce(0) { $0 + $1.tss }

            // Calculate new CTL and ATL
            let newCTL = PMCCalculator.calculateCTL(previousCTL: previousCTL, todayTSS: dailyTSS)
            let newATL = PMCCalculator.calculateATL(previousATL: previousATL, todayTSS: dailyTSS)
            let newTSB = newCTL - newATL

            // Get or create DailyMetrics for this day
            let metricsPredicate = #Predicate<DailyMetrics> { metrics in
                metrics.date >= currentDate && metrics.date < nextDate
            }
            let metricsDescriptor = FetchDescriptor<DailyMetrics>(predicate: metricsPredicate)

            let existingMetrics = try? modelContext.fetch(metricsDescriptor)

            if let metrics = existingMetrics?.first {
                // Update existing
                metrics.totalTSS = dailyTSS
                metrics.ctl = newCTL
                metrics.atl = newATL
                metrics.tsb = newTSB
            } else {
                // Create new
                let metrics = DailyMetrics(
                    date: currentDate,
                    totalTSS: dailyTSS,
                    ctl: newCTL,
                    atl: newATL,
                    tsb: newTSB,
                    source: .calculated
                )
                modelContext.insert(metrics)
            }

            // Update for next iteration
            previousCTL = newCTL
            previousATL = newATL
            currentDate = nextDate
        }
    }

    // MARK: - Wellness Data Sync

    private func syncWellnessData(modelContext: ModelContext, from startDate: Date) async {
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())

        while currentDate <= today {
            let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!

            // Get or create DailyMetrics for this day
            let predicate = #Predicate<DailyMetrics> { metrics in
                metrics.date >= currentDate && metrics.date < nextDate
            }
            let descriptor = FetchDescriptor<DailyMetrics>(predicate: predicate)

            var metrics: DailyMetrics
            if let existing = try? modelContext.fetch(descriptor).first {
                metrics = existing
            } else {
                metrics = DailyMetrics(
                    date: currentDate,
                    totalTSS: 0,
                    ctl: 0,
                    atl: 0,
                    tsb: 0,
                    source: .calculated
                )
                modelContext.insert(metrics)
            }

            // Fetch HRV
            if let hrv = await fetchHRV(for: currentDate) {
                metrics.hrvRMSSD = hrv
            }

            // Fetch Resting HR
            if let rhr = await fetchRestingHR(for: currentDate) {
                metrics.restingHR = rhr
            }

            // Fetch Sleep
            if let sleepData = await fetchSleep(for: currentDate) {
                metrics.sleepHours = sleepData.totalSleepHours
                metrics.sleepQuality = sleepData.qualityScore
                metrics.deepSleepMinutes = sleepData.deepSleepMinutes
                metrics.remSleepMinutes = sleepData.remSleepMinutes
                metrics.sleepEfficiency = sleepData.efficiency
            }

            // Fetch Steps
            if let steps = await fetchSteps(for: currentDate) {
                metrics.steps = steps
            }

            // Fetch Active Calories
            if let calories = await fetchActiveCalories(for: currentDate) {
                metrics.activeCalories = calories
            }

            // Calculate readiness score
            metrics.readinessScore = calculateReadinessScore(metrics: metrics)

            currentDate = nextDate
        }
    }

    private func fetchHRV(for date: Date) async -> Double? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        do {
            let samples = try await healthKitService.fetchHRV(from: startOfDay, to: endOfDay)
            guard !samples.isEmpty else { return nil }

            let values = samples.map { $0.quantity.doubleValue(for: .secondUnit(with: .milli)) }
            return values.reduce(0, +) / Double(values.count)
        } catch {
            return nil
        }
    }

    private func fetchRestingHR(for date: Date) async -> Int? {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        do {
            let samples = try await healthKitService.fetchRestingHeartRate(from: startOfDay, to: endOfDay)
            guard !samples.isEmpty else { return nil }

            let values = samples.map { Int($0.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))) }
            return values.min() // Use lowest resting HR of the day
        } catch {
            return nil
        }
    }

    private func fetchSleep(for date: Date) async -> SleepData? {
        do {
            let samples = try await healthKitService.fetchSleepAnalysis(for: date)
            guard !samples.isEmpty else { return nil }
            return healthKitService.parseSleepData(from: samples)
        } catch {
            return nil
        }
    }

    private func fetchSteps(for date: Date) async -> Int? {
        do {
            let steps = try await healthKitService.fetchSteps(for: date)
            return Int(steps)
        } catch {
            return nil
        }
    }

    private func fetchActiveCalories(for date: Date) async -> Double? {
        do {
            return try await healthKitService.fetchActiveCalories(for: date)
        } catch {
            return nil
        }
    }

    private func calculateReadinessScore(metrics: DailyMetrics) -> Double {
        var score = 70.0 // Base score
        var factors = 0

        // HRV factor (weight: 30%)
        if let hrv = metrics.hrvRMSSD {
            // Assume 40-60ms is normal range
            let hrvScore = min(100, max(0, (hrv - 20) * 2))
            score += hrvScore * 0.3
            factors += 1
        }

        // Sleep factor (weight: 25%)
        if let sleepQuality = metrics.sleepQuality {
            score += sleepQuality * 100 * 0.25
            factors += 1
        }

        // RHR factor (weight: 15%)
        if let rhr = metrics.restingHR {
            // Lower is better, assume 50-70 is normal
            let rhrScore = max(0, 100 - Double(rhr - 40) * 2)
            score += rhrScore * 0.15
            factors += 1
        }

        // TSB factor (weight: 15%)
        let tsbScore = min(100, max(0, 50 + metrics.tsb * 2))
        score += tsbScore * 0.15
        factors += 1

        return factors > 0 ? min(100, max(0, score)) : 70
    }

    // MARK: - Helper Methods

    private func workoutActivityName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .swimming: return "Swimming"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "Strength"
        case .yoga: return "Yoga"
        case .rowing: return "Rowing"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stair Climbing"
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining: return "Core Training"
        case .crossTraining: return "Cross Training"
        default: return "Workout"
        }
    }

    private func activityCategory(for type: HKWorkoutActivityType) -> ActivityCategory {
        switch type {
        case .running, .walking, .hiking: return .run
        case .cycling: return .bike
        case .swimming: return .swim
        case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining: return .strength
        default: return .other
        }
    }

    // MARK: - Auto-Detect Thresholds

    /// Analyze synced workouts to estimate athlete thresholds
    func autoDetectThresholds(modelContext: ModelContext) async -> DetectedThresholds {
        var detected = DetectedThresholds()

        // Fetch all workouts with power data
        let descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )

        guard let workouts = try? modelContext.fetch(descriptor) else {
            return detected
        }

        // Estimate cycling FTP from best 20-min power efforts
        let cyclingWorkouts = workouts.filter { $0.activityCategory == .bike && $0.normalizedPower != nil }
        if !cyclingWorkouts.isEmpty {
            // Use best NP as proxy (real FTP test would be 95% of 20-min power)
            let bestNP = cyclingWorkouts.compactMap { $0.normalizedPower }.max() ?? 0
            if bestNP > 100 {
                detected.estimatedFTP = Int(Double(bestNP) * 0.95)
            }
        }

        // Estimate running FTP
        let runningWorkouts = workouts.filter { $0.activityCategory == .run && $0.normalizedPower != nil }
        if !runningWorkouts.isEmpty {
            let bestRunNP = runningWorkouts.compactMap { $0.normalizedPower }.max() ?? 0
            if bestRunNP > 150 {
                detected.estimatedRunningFTP = Int(Double(bestRunNP) * 0.95)
            }
        }

        // Estimate threshold HR from high-intensity workouts
        let intensiveWorkouts = workouts.filter { $0.intensityFactor > 0.85 && $0.averageHeartRate != nil }
        if !intensiveWorkouts.isEmpty {
            let avgHRs = intensiveWorkouts.compactMap { $0.averageHeartRate }
            let meanHighIntensityHR = avgHRs.reduce(0, +) / avgHRs.count
            detected.estimatedLTHR = meanHighIntensityHR
        }

        // Estimate max HR from all workouts
        let allMaxHRs = workouts.compactMap { $0.averageHeartRate }.filter { $0 > 150 }
        if let maxRecorded = allMaxHRs.max() {
            // Add a small buffer since avg HR won't hit true max
            detected.estimatedMaxHR = min(220, maxRecorded + 10)
        }

        // Estimate threshold pace from running workouts
        let pacedRuns = workouts.filter {
            $0.activityCategory == .run &&
            $0.distanceMeters ?? 0 > 3000 &&
            $0.intensityFactor > 0.8
        }
        if !pacedRuns.isEmpty {
            let paces = pacedRuns.compactMap { workout -> Double? in
                guard let distance = workout.distanceMeters, distance > 0 else { return nil }
                return workout.durationSeconds / (distance / 1000) // sec per km
            }
            if let avgThresholdPace = paces.sorted().dropFirst(paces.count / 4).first {
                detected.estimatedThresholdPace = avgThresholdPace
            }
        }

        detected.workoutsAnalyzed = workouts.count

        return detected
    }

    // MARK: - Sync Statistics Query

    /// Get current workout counts from database
    func getWorkoutCounts(modelContext: ModelContext) -> WorkoutCounts {
        var counts = WorkoutCounts()

        let descriptor = FetchDescriptor<WorkoutRecord>()
        guard let workouts = try? modelContext.fetch(descriptor) else {
            return counts
        }

        counts.total = workouts.count

        // Count by category
        for workout in workouts {
            counts.byCategory[workout.activityCategory, default: 0] += 1
            counts.byTSSType[workout.tssType, default: 0] += 1
        }

        // Date range
        counts.earliestDate = workouts.map { $0.startDate }.min()
        counts.latestDate = workouts.map { $0.startDate }.max()

        return counts
    }
}

// MARK: - Supporting Types

/// Real-time sync progress
struct SyncProgress {
    var phase: SyncPhase = .idle
    var totalWorkouts: Int = 0
    var processedWorkouts: Int = 0
    var workoutsByType: [ActivityCategory: Int] = [:]
    var workoutsByTSSType: [TSSType: Int] = [:]

    var progressPercent: Double {
        guard totalWorkouts > 0 else { return 0 }
        return Double(processedWorkouts) / Double(totalWorkouts)
    }

    var statusText: String {
        switch phase {
        case .idle: return "Ready"
        case .fetchingWorkouts: return "Fetching workouts from Health..."
        case .processingWorkouts: return "Processing \(processedWorkouts)/\(totalWorkouts) workouts..."
        case .calculatingPMC: return "Calculating fitness metrics..."
        case .syncingWellness: return "Syncing wellness data..."
        case .complete: return "Sync complete"
        }
    }
}

enum SyncPhase: String, Codable {
    case idle
    case fetchingWorkouts
    case processingWorkouts
    case calculatingPMC
    case syncingWellness
    case complete
}

/// Persisted sync statistics
struct SyncStatistics: Codable {
    var totalSyncs: Int = 0
    var lastSyncDate: Date?
    var lastSyncWorkoutCount: Int = 0
    var totalWorkoutsSynced: Int = 0
}

/// Result from processing a single workout
struct WorkoutProcessResult {
    var wasInserted: Bool
    var category: ActivityCategory
    var tssType: TSSType
}

/// Auto-detected threshold values
struct DetectedThresholds {
    var estimatedFTP: Int?
    var estimatedRunningFTP: Int?
    var estimatedLTHR: Int?
    var estimatedMaxHR: Int?
    var estimatedThresholdPace: Double?
    var workoutsAnalyzed: Int = 0

    var hasAnyEstimates: Bool {
        estimatedFTP != nil || estimatedRunningFTP != nil ||
        estimatedLTHR != nil || estimatedMaxHR != nil ||
        estimatedThresholdPace != nil
    }

    /// Format threshold pace as mm:ss/km
    var thresholdPaceFormatted: String? {
        guard let pace = estimatedThresholdPace else { return nil }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }
}

/// Current workout counts from database
struct WorkoutCounts {
    var total: Int = 0
    var byCategory: [ActivityCategory: Int] = [:]
    var byTSSType: [TSSType: Int] = [:]
    var earliestDate: Date?
    var latestDate: Date?

    var dateRangeFormatted: String? {
        guard let earliest = earliestDate, let latest = latestDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: earliest)) - \(formatter.string(from: latest))"
    }
}
