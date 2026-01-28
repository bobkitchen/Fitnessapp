//
//  HealthKitRouteService.swift
//  FitnessApp
//
//  Handles GPS route data from HealthKit workouts.
//

import Foundation
import HealthKit
import CoreLocation

/// Service for fetching and processing workout route data from HealthKit.
final class HealthKitRouteService {

    private let core: HealthKitCore

    init(core: HealthKitCore = .shared) {
        self.core = core
    }

    // MARK: - Route Queries

    /// Fetch GPS route locations for an HKWorkout
    func fetchWorkoutRoute(for workout: HKWorkout) async throws -> [CLLocation] {
        let routes = try await fetchWorkoutRouteObjects(for: workout)
        guard let route = routes.first else { return [] }
        return try await fetchRouteLocations(from: route)
    }

    /// Fetch HKWorkoutRoute objects linked to a workout
    private func fetchWorkoutRouteObjects(for workout: HKWorkout) async throws -> [HKWorkoutRoute] {
        let routeType = HKSeriesType.workoutRoute()
        let predicate = HKQuery.predicateForObjects(from: workout)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: routeType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let routes = samples as? [HKWorkoutRoute] ?? []
                continuation.resume(returning: routes)
            }
            core.healthStore.execute(query)
        }
    }

    /// Extract CLLocation array from an HKWorkoutRoute
    private func fetchRouteLocations(from route: HKWorkoutRoute) async throws -> [CLLocation] {
        try await withCheckedThrowingContinuation { continuation in
            var allLocations: [CLLocation] = []

            let query = HKWorkoutRouteQuery(route: route) { _, locations, done, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if let locations {
                    allLocations.append(contentsOf: locations)
                }

                if done {
                    continuation.resume(returning: allLocations)
                }
            }
            core.healthStore.execute(query)
        }
    }

    // MARK: - Route Processing

    /// Downsample locations to a target number of points for storage efficiency.
    /// Uses linear interpolation to maintain route shape.
    static func downsampleLocations(_ locations: [CLLocation], maxPoints: Int = 300) -> [CLLocation] {
        guard locations.count > maxPoints else { return locations }

        let step = Double(locations.count - 1) / Double(maxPoints - 1)
        var result: [CLLocation] = []
        result.reserveCapacity(maxPoints)

        for i in 0..<maxPoints {
            let index = Int((Double(i) * step).rounded())
            result.append(locations[min(index, locations.count - 1)])
        }

        return result
    }

    /// Calculate total distance from a route
    static func calculateDistance(from locations: [CLLocation]) -> Double {
        guard locations.count >= 2 else { return 0 }

        var totalDistance: Double = 0
        for i in 1..<locations.count {
            totalDistance += locations[i].distance(from: locations[i - 1])
        }
        return totalDistance
    }

    /// Calculate elevation gain from a route
    static func calculateElevationGain(from locations: [CLLocation]) -> Double {
        guard locations.count >= 2 else { return 0 }

        var totalGain: Double = 0
        for i in 1..<locations.count {
            let elevationDiff = locations[i].altitude - locations[i - 1].altitude
            if elevationDiff > 0 {
                totalGain += elevationDiff
            }
        }
        return totalGain
    }

    /// Calculate elevation loss from a route
    static func calculateElevationLoss(from locations: [CLLocation]) -> Double {
        guard locations.count >= 2 else { return 0 }

        var totalLoss: Double = 0
        for i in 1..<locations.count {
            let elevationDiff = locations[i].altitude - locations[i - 1].altitude
            if elevationDiff < 0 {
                totalLoss += abs(elevationDiff)
            }
        }
        return totalLoss
    }

    /// Get bounding box for a route
    static func boundingBox(for locations: [CLLocation]) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        guard !locations.isEmpty else { return nil }

        var minLat = locations[0].coordinate.latitude
        var maxLat = locations[0].coordinate.latitude
        var minLon = locations[0].coordinate.longitude
        var maxLon = locations[0].coordinate.longitude

        for location in locations {
            minLat = min(minLat, location.coordinate.latitude)
            maxLat = max(maxLat, location.coordinate.latitude)
            minLon = min(minLon, location.coordinate.longitude)
            maxLon = max(maxLon, location.coordinate.longitude)
        }

        return (minLat, maxLat, minLon, maxLon)
    }
}
