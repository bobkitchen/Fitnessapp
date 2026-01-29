//
//  StravaSyncService.swift
//  FitnessApp
//
//  Syncs workouts from Strava as the primary workout source.
//  Creates new WorkoutRecords from Strava activities and auto-calculates TSS.
//

import Foundation
import SwiftData
import CoreLocation

// MARK: - Strava Sync Service

@Observable
@MainActor
final class StravaSyncService {

    private let stravaService: StravaService
    private let modelContext: ModelContext

    // Sync state
    var isSyncing = false
    var syncProgress: Double = 0
    var lastSyncResult: StravaSyncResult?
    var syncError: String?

    /// Auto-sync interval: 1 hour
    private static let autoSyncInterval: TimeInterval = 3600

    init(stravaService: StravaService, modelContext: ModelContext) {
        self.stravaService = stravaService
        self.modelContext = modelContext
    }

    // MARK: - Auto-Sync

    /// Whether enough time has passed since the last sync to auto-sync
    var shouldAutoSync: Bool {
        guard stravaService.isAuthenticated else { return false }
        guard let lastSync = Self.lastSyncDate else { return true }
        return Date().timeIntervalSince(lastSync) > Self.autoSyncInterval
    }

    /// Persisted last sync date
    static var lastSyncDate: Date? {
        get { UserDefaults.standard.object(forKey: UserDefaultsKey.lastStravaSyncDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: UserDefaultsKey.lastStravaSyncDate.rawValue) }
    }

    /// Auto-sync: fetches activities since last sync (or 12 months for initial)
    func autoSync() async {
        // Validate token is actually usable before checking shouldAutoSync
        await stravaService.validateAuthentication()
        guard shouldAutoSync else { return }

        do {
            if Self.lastSyncDate == nil {
                // Initial sync: fetch 12 months of history
                _ = try await syncAllActivities()
            } else {
                // Incremental sync: fetch since last sync
                _ = try await syncRecentActivities()
            }
        } catch {
            print("[StravaSyncService] Auto-sync failed: \(error.localizedDescription)")
            syncError = error.localizedDescription
        }
    }

    // MARK: - Sync Operations

    /// Initial full sync: fetches all activities with pagination (12-month cap)
    func syncAllActivities() async throws -> StravaSyncResult {
        guard stravaService.isAuthenticated else {
            throw StravaError.notAuthenticated
        }

        isSyncing = true
        syncProgress = 0
        syncError = nil

        defer { isSyncing = false }

        let activities = try await stravaService.fetchAllActivities()
        syncProgress = 0.3

        return try await processActivities(activities)
    }

    /// Incremental sync: fetches activities since last sync date
    func syncRecentActivities() async throws -> StravaSyncResult {
        guard stravaService.isAuthenticated else {
            throw StravaError.notAuthenticated
        }

        isSyncing = true
        syncProgress = 0
        syncError = nil

        defer { isSyncing = false }

        let afterDate = Self.lastSyncDate ?? Calendar.current.date(byAdding: .month, value: -12, to: Date())!
        let activities = try await stravaService.fetchActivities(after: afterDate)
        syncProgress = 0.3

        return try await processActivities(activities)
    }

    /// Process fetched activities: create-first logic
    private func processActivities(_ activities: [StravaActivity]) async throws -> StravaSyncResult {
        let profile = try fetchAthleteProfile()

        var newCount = 0
        var skippedCount = 0
        var errors: [String] = []

        let totalActivities = max(activities.count, 1)

        for (index, activity) in activities.enumerated() {
            syncProgress = 0.3 + (0.7 * Double(index) / Double(totalActivities))

            do {
                let result = try processActivity(activity, profile: profile)
                switch result {
                case .created:
                    newCount += 1
                case .skipped:
                    skippedCount += 1
                }
            } catch {
                errors.append("Activity '\(activity.displayName)': \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        syncProgress = 1.0

        // Update last sync date
        Self.lastSyncDate = Date()

        let result = StravaSyncResult(
            newActivities: newCount,
            enrichedActivities: 0,
            skippedActivities: skippedCount,
            totalProcessed: activities.count,
            errors: errors
        )

        lastSyncResult = result
        print("[StravaSyncService] Sync complete: \(result.summary)")

        return result
    }

    /// Process a single Strava activity: create-first logic
    /// - If stravaActivityId already exists -> skip
    /// - Otherwise -> create new WorkoutRecord with auto-calculated TSS
    private func processActivity(
        _ activity: StravaActivity,
        profile: AthleteProfile?
    ) throws -> SyncResultType {
        // Check if this Strava activity already exists
        let activityId = activity.id
        let predicate = #Predicate<WorkoutRecord> { workout in
            workout.stravaActivityId == activityId
        }
        let descriptor = FetchDescriptor<WorkoutRecord>(predicate: predicate)
        let existing = try modelContext.fetch(descriptor)

        if !existing.isEmpty {
            return .skipped
        }

        // Create new workout from Strava
        let workout = createWorkout(from: activity, profile: profile)
        modelContext.insert(workout)
        return .created
    }

    /// Create a new WorkoutRecord from a Strava activity with auto-calculated TSS
    private func createWorkout(from activity: StravaActivity, profile: AthleteProfile?) -> WorkoutRecord {
        let endDate = activity.startDate.addingTimeInterval(activity.durationSeconds)

        let workout = WorkoutRecord(
            activityType: activity.activityType,
            activityCategory: activity.activityCategory,
            title: activity.displayName,
            startDate: activity.startDate,
            endDate: endDate,
            durationSeconds: activity.durationSeconds,
            distanceMeters: activity.distanceMeters,
            tss: 0,
            tssType: .estimated,
            indoorWorkout: activity.trainer ?? false,
            hasRoute: false
        )

        // Link to Strava
        workout.stravaActivityId = activity.id
        workout.source = .strava

        // Add route data
        if let polyline = activity.map?.summaryPolyline {
            let coordinates = PolylineDecoder.decode(polyline)
            if !coordinates.isEmpty {
                workout.routeData = WorkoutRecord.encodeRoute(coordinates)
                workout.hasRoute = true
            }
        }

        // Add metrics from Strava
        if let avgHR = activity.averageHeartrate {
            workout.averageHeartRate = Int(avgHR)
        }
        if let maxHR = activity.maxHeartrate {
            workout.maxHeartRate = Int(maxHR)
        }
        if let avgWatts = activity.averageWatts {
            workout.averagePower = Int(avgWatts)
        }
        if let maxWatts = activity.maxWatts {
            workout.maxPower = maxWatts
        }
        if let np = activity.weightedAverageWatts {
            workout.normalizedPower = np
        }
        if let cadence = activity.averageCadence {
            workout.averageCadence = Int(cadence)
        }
        if let elevation = activity.totalElevationGain {
            workout.totalAscent = elevation
        }
        if let kj = activity.kilojoules {
            workout.activeCalories = kj
        }

        // Calculate pace for runs
        if activity.activityCategory == .run && activity.distanceMeters > 0 {
            let paceSecondsPerKm = activity.durationSeconds / (activity.distanceMeters / 1000)
            workout.averagePaceSecondsPerKm = paceSecondsPerKm
        }

        // Auto-calculate TSS using best available data
        let tssResult = calculateTSS(for: activity, profile: profile)
        workout.tss = tssResult.tss
        workout.tssType = tssResult.type
        workout.intensityFactor = tssResult.intensityFactor
        workout.calculatedTSS = tssResult.tss

        // All new workouts start as pending verification
        workout.tssVerificationStatus = .pending

        return workout
    }

    /// Calculate TSS from Strava activity data using TSSCalculator
    private func calculateTSS(for activity: StravaActivity, profile: AthleteProfile?) -> TSSResult {
        let duration = activity.durationSeconds
        guard duration > TSSConstants.minimumDurationForTSS else {
            return TSSResult(tss: 0, type: .estimated, intensityFactor: 0)
        }

        // Cycling with power
        if activity.activityCategory == .bike,
           let np = activity.weightedAverageWatts,
           let ftp = profile?.ftpWatts, ftp > 0 {
            return TSSCalculator.calculatePowerTSS(
                normalizedPower: np,
                durationSeconds: duration,
                ftp: ftp
            )
        }

        // Running with power
        if activity.activityCategory == .run,
           let np = activity.weightedAverageWatts,
           let runFTP = profile?.runningFTPWatts, runFTP > 0 {
            return TSSCalculator.calculateRunningPowerTSS(
                normalizedPower: np,
                durationSeconds: duration,
                runningFTP: runFTP
            )
        }

        // Running with pace
        if activity.activityCategory == .run,
           activity.distanceMeters > 0,
           let thresholdPace = profile?.thresholdPaceSecondsPerKm {
            let avgPace = duration / (activity.distanceMeters / 1000)
            return TSSCalculator.calculateRunningTSS(
                averagePace: avgPace,
                durationSeconds: duration,
                thresholdPace: thresholdPace,
                totalAscent: activity.totalElevationGain,
                totalDescent: nil,
                distance: activity.distanceMeters
            )
        }

        // Swimming with pace
        if activity.activityCategory == .swim,
           activity.distanceMeters > 0,
           let swimThreshold = profile?.swimThresholdPacePer100m {
            let avgPace = duration / (activity.distanceMeters / 100)
            return TSSCalculator.calculateSwimTSS(
                averagePacePer100m: avgPace,
                durationSeconds: duration,
                thresholdPacePer100m: swimThreshold
            )
        }

        // Heart rate based
        if let avgHR = activity.averageHeartrate,
           let thresholdHR = profile?.thresholdHeartRate, thresholdHR > 0 {
            let hrIF = avgHR / Double(thresholdHR)
            let tss = (duration / 3600) * pow(hrIF, 2) * 100
            return TSSResult(tss: tss, type: .heartRate, intensityFactor: hrIF)
        }

        // Estimate based on activity type and duration
        let estimatedIntensity: Double
        switch activity.activityCategory {
        case .run: estimatedIntensity = 0.7
        case .bike: estimatedIntensity = 0.65
        case .swim: estimatedIntensity = 0.7
        case .strength: estimatedIntensity = 0.6
        case .other: estimatedIntensity = 0.5
        }

        return TSSCalculator.estimateTSS(
            durationSeconds: duration,
            perceivedIntensity: estimatedIntensity
        )
    }

    // MARK: - Data Fetching

    private func fetchAthleteProfile() throws -> AthleteProfile? {
        let descriptor = FetchDescriptor<AthleteProfile>()
        return try modelContext.fetch(descriptor).first
    }

    // MARK: - Result Types

    private enum SyncResultType {
        case created
        case skipped
    }
}

// MARK: - Sync Result

struct StravaSyncResult {
    let newActivities: Int
    let enrichedActivities: Int
    let skippedActivities: Int
    let totalProcessed: Int
    let errors: [String]

    var summary: String {
        var parts: [String] = []
        if newActivities > 0 {
            parts.append("\(newActivities) new")
        }
        if enrichedActivities > 0 {
            parts.append("\(enrichedActivities) enriched")
        }
        if skippedActivities > 0 {
            parts.append("\(skippedActivities) skipped")
        }
        if !errors.isEmpty {
            parts.append("\(errors.count) errors")
        }
        return parts.isEmpty ? "No activities" : parts.joined(separator: ", ")
    }
}

// MARK: - Polyline Decoder

/// Decodes Google Encoded Polyline format used by Strava
enum PolylineDecoder {

    /// Decode a polyline string into coordinates
    static func decode(_ polyline: String) -> [(latitude: Double, longitude: Double)] {
        var coordinates: [(Double, Double)] = []
        var index = polyline.startIndex
        var lat = 0
        var lng = 0

        while index < polyline.endIndex {
            // Decode latitude
            var result = 0
            var shift = 0
            var byte: Int

            repeat {
                byte = Int(polyline[index].asciiValue! - 63)
                index = polyline.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20 && index < polyline.endIndex

            let deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += deltaLat

            guard index < polyline.endIndex else { break }

            // Decode longitude
            result = 0
            shift = 0

            repeat {
                byte = Int(polyline[index].asciiValue! - 63)
                index = polyline.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
            } while byte >= 0x20 && index < polyline.endIndex

            let deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lng += deltaLng

            let latitude = Double(lat) / 1e5
            let longitude = Double(lng) / 1e5
            coordinates.append((latitude, longitude))
        }

        return coordinates
    }

    /// Encode coordinates to a polyline string
    static func encode(_ coordinates: [(latitude: Double, longitude: Double)]) -> String {
        var result = ""
        var prevLat = 0
        var prevLng = 0

        for coord in coordinates {
            let lat = Int(round(coord.latitude * 1e5))
            let lng = Int(round(coord.longitude * 1e5))

            result += encodeValue(lat - prevLat)
            result += encodeValue(lng - prevLng)

            prevLat = lat
            prevLng = lng
        }

        return result
    }

    private static func encodeValue(_ value: Int) -> String {
        var v = value < 0 ? ~(value << 1) : (value << 1)
        var result = ""

        while v >= 0x20 {
            result += String(UnicodeScalar((0x20 | (v & 0x1F)) + 63)!)
            v >>= 5
        }
        result += String(UnicodeScalar(v + 63)!)

        return result
    }
}
