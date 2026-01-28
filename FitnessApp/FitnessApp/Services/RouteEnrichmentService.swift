import Foundation
import HealthKit
import SwiftData
import CoreLocation

/// Result of a route enrichment pass
struct RouteEnrichmentResult {
    let totalWorkouts: Int
    let matchedCount: Int
    let enrichedCount: Int
    let noRouteInHealthKit: Int
    let unmatchedCount: Int
    let errors: [String]

    var summary: String {
        var parts: [String] = []
        if enrichedCount > 0 { parts.append("\(enrichedCount) routes added") }
        if noRouteInHealthKit > 0 { parts.append("\(noRouteInHealthKit) had no GPS data") }
        if unmatchedCount > 0 { parts.append("\(unmatchedCount) unmatched") }
        if !errors.isEmpty { parts.append("\(errors.count) errors") }
        return parts.isEmpty ? "No outdoor workouts to enrich" : parts.joined(separator: ", ")
    }
}

/// Enriches WorkoutRecord entries with GPS route data from HealthKit
@Observable @MainActor
final class RouteEnrichmentService {
    private let healthKitService: HealthKitService
    var isEnriching = false
    var progress: Double = 0
    var lastResult: RouteEnrichmentResult?

    init(healthKitService: HealthKitService) {
        self.healthKitService = healthKitService
    }

    /// Enrich all eligible workouts in a date range with GPS routes from HealthKit
    func enrichRoutes(modelContext: ModelContext, dateRange: ClosedRange<Date>? = nil) async -> RouteEnrichmentResult {
        isEnriching = true
        progress = 0
        defer {
            isEnriching = false
        }

        // 1. Fetch WorkoutRecords without routes that are outdoor
        let records = fetchEligibleRecords(modelContext: modelContext, dateRange: dateRange)
        guard !records.isEmpty else {
            let result = RouteEnrichmentResult(
                totalWorkouts: 0, matchedCount: 0, enrichedCount: 0,
                noRouteInHealthKit: 0, unmatchedCount: 0, errors: []
            )
            lastResult = result
            return result
        }

        // 2. Determine the date span and fetch HKWorkouts
        let earliest = records.map(\.startDate).min()!
        let latest = records.map(\.endDate).max()!
        let fetchStart = Calendar.current.date(byAdding: .day, value: -1, to: earliest)!
        let fetchEnd = Calendar.current.date(byAdding: .day, value: 1, to: latest)!

        let hkWorkouts: [HKWorkout]
        do {
            hkWorkouts = try await healthKitService.fetchWorkouts(from: fetchStart, to: fetchEnd)
        } catch {
            let result = RouteEnrichmentResult(
                totalWorkouts: records.count, matchedCount: 0, enrichedCount: 0,
                noRouteInHealthKit: 0, unmatchedCount: records.count,
                errors: ["Failed to fetch HealthKit workouts: \(error.localizedDescription)"]
            )
            lastResult = result
            return result
        }

        // 3. Match and enrich each record
        var matchedCount = 0
        var enrichedCount = 0
        var noRouteCount = 0
        var errors: [String] = []

        for (index, record) in records.enumerated() {
            progress = Double(index) / Double(records.count)

            guard let bestMatch = findBestMatch(for: record, in: hkWorkouts) else {
                continue
            }
            matchedCount += 1

            do {
                let locations = try await healthKitService.fetchWorkoutRoute(for: bestMatch)
                guard !locations.isEmpty else {
                    noRouteCount += 1
                    continue
                }

                let downsampled = HealthKitService.downsampleLocations(locations)
                let coords = downsampled.map { (latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
                if let encoded = WorkoutRecord.encodeRoute(coords) {
                    record.routeData = encoded
                    record.hasRoute = true
                    enrichedCount += 1
                }
            } catch {
                errors.append("\(record.title ?? record.activityType) on \(record.dateFormatted): \(error.localizedDescription)")
            }
        }

        progress = 1.0

        // 4. Save
        try? modelContext.save()

        let unmatchedCount = records.count - matchedCount
        let result = RouteEnrichmentResult(
            totalWorkouts: records.count,
            matchedCount: matchedCount,
            enrichedCount: enrichedCount,
            noRouteInHealthKit: noRouteCount,
            unmatchedCount: unmatchedCount,
            errors: errors
        )
        lastResult = result
        return result
    }

    /// Enrich a single workout record with GPS route data from HealthKit
    func enrichSingleWorkout(_ workout: WorkoutRecord, modelContext: ModelContext) async -> Bool {
        let fetchStart = Calendar.current.date(byAdding: .day, value: -1, to: workout.startDate)!
        let fetchEnd = Calendar.current.date(byAdding: .day, value: 1, to: workout.endDate)!

        guard let hkWorkouts = try? await healthKitService.fetchWorkouts(from: fetchStart, to: fetchEnd) else {
            return false
        }

        guard let bestMatch = findBestMatch(for: workout, in: hkWorkouts) else {
            return false
        }

        do {
            let locations = try await healthKitService.fetchWorkoutRoute(for: bestMatch)
            guard !locations.isEmpty else { return false }

            let downsampled = HealthKitService.downsampleLocations(locations)
            let coords = downsampled.map { (latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude) }
            if let encoded = WorkoutRecord.encodeRoute(coords) {
                workout.routeData = encoded
                workout.hasRoute = true
                try? modelContext.save()
                return true
            }
        } catch {
            print("[RouteEnrichment] Error fetching route: \(error.localizedDescription)")
        }

        return false
    }

    // MARK: - Private Methods

    private func fetchEligibleRecords(modelContext: ModelContext, dateRange: ClosedRange<Date>?) -> [WorkoutRecord] {
        let descriptor: FetchDescriptor<WorkoutRecord>
        if let range = dateRange {
            let start = range.lowerBound
            let end = range.upperBound
            descriptor = FetchDescriptor<WorkoutRecord>(
                predicate: #Predicate<WorkoutRecord> {
                    $0.hasRoute == false &&
                    $0.indoorWorkout == false &&
                    $0.startDate >= start &&
                    $0.startDate <= end
                },
                sortBy: [SortDescriptor(\.startDate, order: .forward)]
            )
        } else {
            descriptor = FetchDescriptor<WorkoutRecord>(
                predicate: #Predicate<WorkoutRecord> {
                    $0.hasRoute == false &&
                    $0.indoorWorkout == false
                },
                sortBy: [SortDescriptor(\.startDate, order: .forward)]
            )
        }

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Find the best matching HKWorkout for a WorkoutRecord
    private func findBestMatch(for record: WorkoutRecord, in hkWorkouts: [HKWorkout]) -> HKWorkout? {
        let calendar = Calendar.current

        // Determine if the record has a precise time or is midnight (CSV import default)
        let hour = calendar.component(.hour, from: record.startDate)
        let minute = calendar.component(.minute, from: record.startDate)
        let hasMidnightTime = hour == 0 && minute == 0

        var bestWorkout: HKWorkout?
        var bestScore: Double = 0

        let recordCategory = record.activityCategory

        for hkWorkout in hkWorkouts {
            var score: Double = 0

            // Time matching
            let sameDay = calendar.isDate(hkWorkout.startDate, inSameDayAs: record.startDate)

            if hasMidnightTime {
                if sameDay {
                    score += 40
                } else {
                    continue
                }
            } else {
                let timeDiff = abs(hkWorkout.startDate.timeIntervalSince(record.startDate))
                if timeDiff < 60 {
                    score += 50
                } else if timeDiff < 120 {
                    score += 35
                } else if timeDiff < 300 {
                    score += 20
                } else if sameDay {
                    score += 10
                } else {
                    continue
                }
            }

            // Duration matching (30 points max)
            let hkDuration = hkWorkout.duration
            let durationDiff = abs(record.durationSeconds - hkDuration) / max(1, hkDuration)
            if durationDiff < 0.02 {
                score += 30
            } else if durationDiff < 0.05 {
                score += 25
            } else if durationDiff < 0.10 {
                score += 15
            } else if durationDiff < 0.20 {
                score += 5
            }

            // Activity type matching (25 points)
            let hkCategory = Self.activityCategory(from: hkWorkout.workoutActivityType)
            if hkCategory == recordCategory {
                score += 25
            }

            // Distance matching (15 points max)
            if let recordDist = record.distanceMeters, recordDist > 0 {
                let hkDist = hkWorkout.totalDistance?.doubleValue(for: .meter()) ?? 0
                if hkDist > 0 {
                    let distDiff = abs(recordDist - hkDist) / recordDist
                    if distDiff < 0.02 {
                        score += 15
                    } else if distDiff < 0.05 {
                        score += 10
                    } else if distDiff < 0.10 {
                        score += 5
                    }
                }
            }

            // Minimum threshold
            guard score >= 50 else { continue }

            if score > bestScore {
                bestScore = score
                bestWorkout = hkWorkout
            }
        }

        return bestWorkout
    }

    /// Map HKWorkoutActivityType to ActivityCategory
    static func activityCategory(from activityType: HKWorkoutActivityType) -> ActivityCategory {
        switch activityType {
        case .running, .walking, .hiking:
            return .run
        case .cycling:
            return .bike
        case .swimming:
            return .swim
        case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining:
            return .strength
        default:
            return .other
        }
    }
}
