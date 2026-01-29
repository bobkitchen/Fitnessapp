//
//  StravaSyncService.swift
//  FitnessApp
//
//  Syncs workouts from Strava, enriches with route data and titles,
//  and matches with existing HealthKit workouts.
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

    init(stravaService: StravaService, modelContext: ModelContext) {
        self.stravaService = stravaService
        self.modelContext = modelContext
    }

    // MARK: - Sync Operations

    /// Sync recent activities from Strava
    /// - Parameter days: Number of days to look back (default 7)
    func syncRecentActivities(days: Int = 7) async throws -> StravaSyncResult {
        guard stravaService.isAuthenticated else {
            throw StravaError.notAuthenticated
        }

        isSyncing = true
        syncProgress = 0
        syncError = nil

        defer { isSyncing = false }

        let afterDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())

        // Fetch activities from Strava
        // Fetch up to 200 activities (Strava max per page) for comprehensive sync
        let activities = try await stravaService.fetchActivities(after: afterDate, perPage: 200)
        syncProgress = 0.3

        // Fetch existing workouts for matching
        let existingWorkouts = try fetchExistingWorkouts(from: afterDate ?? Date())
        syncProgress = 0.4

        var newCount = 0
        var enrichedCount = 0
        var skippedCount = 0
        var errors: [String] = []

        let totalActivities = activities.count

        for (index, activity) in activities.enumerated() {
            syncProgress = 0.4 + (0.6 * Double(index) / Double(totalActivities))

            do {
                let result = try await processActivity(activity, existingWorkouts: existingWorkouts)
                switch result {
                case .created:
                    newCount += 1
                case .enriched:
                    enrichedCount += 1
                case .skipped:
                    skippedCount += 1
                }
            } catch {
                errors.append("Activity '\(activity.displayName)': \(error.localizedDescription)")
            }
        }

        try modelContext.save()
        syncProgress = 1.0

        let result = StravaSyncResult(
            newActivities: newCount,
            enrichedActivities: enrichedCount,
            skippedActivities: skippedCount,
            totalProcessed: activities.count,
            errors: errors
        )

        lastSyncResult = result
        print("[StravaSyncService] Sync complete: \(result.summary)")

        return result
    }

    /// Process a single Strava activity
    private func processActivity(
        _ activity: StravaActivity,
        existingWorkouts: [WorkoutRecord]
    ) async throws -> SyncResultType {
        // Try to find a matching workout by time/duration
        if let match = findMatchingWorkout(for: activity, in: existingWorkouts) {
            // Enrich existing workout with Strava data
            try await enrichWorkout(match, with: activity)
            return .enriched
        }

        // Check if we already have this Strava activity
        if existingWorkouts.contains(where: { $0.stravaActivityId == activity.id }) {
            return .skipped
        }

        // Create new workout from Strava
        let workout = try await createWorkout(from: activity)
        modelContext.insert(workout)
        return .created
    }

    /// Find a matching workout for a Strava activity using Distance-First Matching
    /// Priority: 1) Same day, 2) Distance within 5% (or 10% with same category), 3) Duration within 2% (cross-category)
    /// Note: Category matching is relaxed because sources categorize activities differently
    private func findMatchingWorkout(
        for activity: StravaActivity,
        in workouts: [WorkoutRecord]
    ) -> WorkoutRecord? {
        let stravaCalendarDay = Calendar.current.startOfDay(for: activity.startDate)
        let stravaDistance = activity.distanceMeters
        let stravaDuration = activity.durationSeconds
        let isIndoor = activity.trainer ?? false

        // Step 1: Filter to candidates on same day, not already linked
        let sameDayCandidates = workouts.filter { workout in
            guard workout.stravaActivityId == nil else { return false }
            let workoutCalendarDay = Calendar.current.startOfDay(for: workout.startDate)
            return workoutCalendarDay == stravaCalendarDay
        }

        guard !sameDayCandidates.isEmpty else { return nil }

        // Step 2: Try distance-first matching (for activities with distance)
        if stravaDistance > 0 {
            let distanceMatches = sameDayCandidates.compactMap { workout -> (workout: WorkoutRecord, distanceDiff: Double, durationDiff: Double, sameCategory: Bool)? in
                guard let workoutDistance = workout.distanceMeters, workoutDistance > 0 else { return nil }

                let distanceDiff = abs(workoutDistance - stravaDistance) / stravaDistance
                let durationDiff = stravaDuration > 0 ? abs(workout.durationSeconds - stravaDuration) / stravaDuration : 0
                let sameCategory = workout.activityCategory == activity.activityCategory

                // Distance match thresholds - allow cross-category for tight matches
                let distanceThreshold = sameCategory ? 0.10 : 0.05
                guard distanceDiff <= distanceThreshold && durationDiff <= 0.25 else { return nil }

                return (workout, distanceDiff, durationDiff, sameCategory)
            }

            if let bestMatch = distanceMatches.min(by: {
                if $0.sameCategory != $1.sameCategory { return $0.sameCategory }
                return $0.distanceDiff < $1.distanceDiff
            }) {
                print("[StravaSyncService] Distance match: \(bestMatch.workout.title ?? "Untitled") " +
                      "(dist diff: \(Int(bestMatch.distanceDiff * 100))%, dur diff: \(Int(bestMatch.durationDiff * 100))%)")
                return bestMatch.workout
            }
        }

        // Step 3: Duration-only matching with same category (moderate threshold)
        let durationMatches = sameDayCandidates.compactMap { workout -> (workout: WorkoutRecord, durationDiff: Double, sameCategory: Bool)? in
            guard workout.activityCategory == activity.activityCategory else { return nil }
            guard stravaDuration > 0 else { return nil }

            let durationDiff = abs(workout.durationSeconds - stravaDuration) / stravaDuration
            guard durationDiff <= 0.10 else { return nil }

            return (workout, durationDiff, true)
        }

        if let bestMatch = durationMatches.min(by: { $0.durationDiff < $1.durationDiff }) {
            print("[StravaSyncService] Duration match (same category): \(bestMatch.workout.title ?? "Untitled") (dur diff: \(Int(bestMatch.durationDiff * 100))%)")
            return bestMatch.workout
        }

        // Step 4: ULTRA-TIGHT duration match - cross-category allowed
        // When durations match within 2%, it's almost certainly the same workout
        // regardless of how each source categorized it (e.g., Badminton vs Other)
        let ultraTightMatches = sameDayCandidates.compactMap { workout -> (workout: WorkoutRecord, durationDiff: Double)? in
            guard stravaDuration > 0 else { return nil }

            let durationDiff = abs(workout.durationSeconds - stravaDuration) / stravaDuration
            // 2% = ~1-2 minutes for a 1-hour workout
            guard durationDiff <= 0.02 else { return nil }

            return (workout, durationDiff)
        }

        if let bestMatch = ultraTightMatches.min(by: { $0.durationDiff < $1.durationDiff }) {
            print("[StravaSyncService] Ultra-tight duration match (cross-category): \(bestMatch.workout.title ?? "Untitled") (dur diff: \(Int(bestMatch.durationDiff * 100))%)")
            return bestMatch.workout
        }

        return nil
    }

    /// Enrich an existing workout with Strava data (route, title, etc.)
    /// Always overwrites: stravaActivityId, title, startDate/endDate, routeData
    /// Preserves: tss, tssType, source (TrainingPeaks data)
    /// Conditionally updates: metrics only if nil
    private func enrichWorkout(_ workout: WorkoutRecord, with activity: StravaActivity) async throws {
        // ALWAYS OVERWRITE: Link to Strava
        workout.stravaActivityId = activity.id

        // ALWAYS OVERWRITE: Title from Strava (has actual workout names)
        if let stravaTitle = activity.name, !stravaTitle.isEmpty {
            workout.title = stravaTitle
        }

        // ALWAYS OVERWRITE: Time from Strava (TP only has date, not time)
        workout.startDate = activity.startDate
        workout.endDate = activity.startDate.addingTimeInterval(activity.durationSeconds)

        // ALWAYS OVERWRITE: Route from Strava
        if let polyline = activity.map?.summaryPolyline {
            let coordinates = PolylineDecoder.decode(polyline)
            if !coordinates.isEmpty {
                workout.routeData = WorkoutRecord.encodeRoute(coordinates)
                workout.hasRoute = true
            }
        }

        // PRESERVE: tss, tssType, source - these come from TrainingPeaks

        // CONDITIONALLY UPDATE: Only fill in missing metrics
        if workout.averageHeartRate == nil, let avgHR = activity.averageHeartrate {
            workout.averageHeartRate = Int(avgHR)
        }
        if workout.maxHeartRate == nil, let maxHR = activity.maxHeartrate {
            workout.maxHeartRate = Int(maxHR)
        }
        if workout.averagePower == nil, let avgWatts = activity.averageWatts {
            workout.averagePower = Int(avgWatts)
        }
        if workout.maxPower == nil, let maxWatts = activity.maxWatts {
            workout.maxPower = maxWatts
        }
        if workout.normalizedPower == nil, let np = activity.weightedAverageWatts {
            workout.normalizedPower = np
        }
        if workout.averageCadence == nil, let cadence = activity.averageCadence {
            workout.averageCadence = Int(cadence)
        }
        if workout.totalAscent == nil, let elevation = activity.totalElevationGain {
            workout.totalAscent = elevation
        }
        if workout.activeCalories == nil, let kj = activity.kilojoules {
            workout.activeCalories = kj
        }
        if workout.averagePaceSecondsPerKm == nil && activity.activityCategory == .run && activity.distanceMeters > 0 {
            let paceSecondsPerKm = activity.durationSeconds / (activity.distanceMeters / 1000)
            workout.averagePaceSecondsPerKm = paceSecondsPerKm
        }

        workout.updatedAt = Date()

        print("[StravaSyncService] Enriched '\(workout.title ?? "Untitled")' with Strava data (route: \(workout.hasRoute), time: \(activity.startDate))")
    }

    /// Create a new WorkoutRecord from a Strava activity
    private func createWorkout(from activity: StravaActivity) async throws -> WorkoutRecord {
        let endDate = activity.startDate.addingTimeInterval(activity.durationSeconds)

        let workout = WorkoutRecord(
            activityType: activity.activityType,
            activityCategory: activity.activityCategory,
            title: activity.displayName,
            startDate: activity.startDate,
            endDate: endDate,
            durationSeconds: activity.durationSeconds,
            distanceMeters: activity.distanceMeters,
            tss: 0,  // Will be calculated
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
            workout.activeCalories = kj  // Approximate: kJ ≈ kcal for cycling
        }

        // Calculate pace for runs
        if activity.activityCategory == .run && activity.distanceMeters > 0 {
            let paceSecondsPerKm = activity.durationSeconds / (activity.distanceMeters / 1000)
            workout.averagePaceSecondsPerKm = paceSecondsPerKm
        }

        // Set TSS verification status to pending
        workout.tssVerificationStatus = .pending

        return workout
    }

    // MARK: - Data Fetching

    private func fetchExistingWorkouts(from startDate: Date) throws -> [WorkoutRecord] {
        let predicate = #Predicate<WorkoutRecord> { workout in
            workout.startDate >= startDate
        }
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - Result Types

    private enum SyncResultType {
        case created
        case enriched
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
