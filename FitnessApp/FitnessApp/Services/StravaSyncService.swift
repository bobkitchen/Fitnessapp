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
        let activities = try await stravaService.fetchActivities(after: afterDate, perPage: 50)
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
                errors.append("Activity '\(activity.name)': \(error.localizedDescription)")
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

    /// Find a matching HealthKit workout for a Strava activity
    private func findMatchingWorkout(
        for activity: StravaActivity,
        in workouts: [WorkoutRecord]
    ) -> WorkoutRecord? {
        // Match by start time (within 5 minutes) and similar duration (within 10%)
        let stravaStart = activity.startDate
        let stravaDuration = activity.durationSeconds

        return workouts.first { workout in
            // Skip if already linked to a Strava activity
            guard workout.stravaActivityId == nil else { return false }

            // Must be same activity category
            guard workout.activityCategory == activity.activityCategory else { return false }

            // Time match: within 5 minutes
            let timeDiff = abs(workout.startDate.timeIntervalSince(stravaStart))
            guard timeDiff < 300 else { return false }

            // Duration match: within 10%
            let durationDiff = abs(workout.durationSeconds - stravaDuration)
            let durationThreshold = stravaDuration * 0.1
            guard durationDiff < durationThreshold else { return false }

            return true
        }
    }

    /// Enrich an existing workout with Strava data (route, title, etc.)
    private func enrichWorkout(_ workout: WorkoutRecord, with activity: StravaActivity) async throws {
        // Link to Strava
        workout.stravaActivityId = activity.id

        // Use Strava title if workout doesn't have one
        if workout.title == nil || workout.title?.isEmpty == true {
            workout.title = activity.name
        }

        // Add route data if available and workout doesn't have one
        if !workout.hasRoute, let polyline = activity.map?.summaryPolyline {
            let coordinates = PolylineDecoder.decode(polyline)
            if !coordinates.isEmpty {
                workout.routeData = WorkoutRecord.encodeRoute(coordinates)
                workout.hasRoute = true
            }
        }

        // Update with additional Strava data
        if workout.totalAscent == nil, let elevation = activity.totalElevationGain {
            workout.totalAscent = elevation
        }

        if workout.normalizedPower == nil, let np = activity.weightedAverageWatts {
            workout.normalizedPower = np
        }

        workout.updatedAt = Date()

        print("[StravaSyncService] Enriched workout '\(workout.title ?? "Untitled")' with Strava data")
    }

    /// Create a new WorkoutRecord from a Strava activity
    private func createWorkout(from activity: StravaActivity) async throws -> WorkoutRecord {
        let endDate = activity.startDate.addingTimeInterval(activity.durationSeconds)

        let workout = WorkoutRecord(
            activityType: activity.type,
            activityCategory: activity.activityCategory,
            title: activity.name,
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
        if activity.activityCategory == .run && activity.distance > 0 {
            let paceSecondsPerKm = activity.durationSeconds / (activity.distance / 1000)
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
