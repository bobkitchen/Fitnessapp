import Foundation
import SwiftData
import CoreLocation

@Model
final class WorkoutRecord {
    var id: UUID
    var healthKitUUID: UUID?                // Reference to HKWorkout UUID
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Basic Workout Info
    var activityType: String                // HKWorkoutActivityType name
    var activityCategoryRaw: String
    var activityCategory: ActivityCategory {
        get { ActivityCategory(rawValue: activityCategoryRaw) ?? .other }
        set { activityCategoryRaw = newValue.rawValue }
    }
    var title: String?                      // Custom workout title
    var startDate: Date
    var endDate: Date
    var durationSeconds: Double
    var distanceMeters: Double?

    // MARK: - TSS Metrics
    var tss: Double                         // Training Stress Score
    var tssTypeRaw: String
    var tssType: TSSType {
        get { TSSType(rawValue: tssTypeRaw) ?? .estimated }
        set { tssTypeRaw = newValue.rawValue }
    }
    var intensityFactor: Double             // IF = NP/FTP or NGP/threshold

    // MARK: - Power Data (Cycling/Running)
    var averagePower: Int?                  // Average power (watts)
    var normalizedPower: Int?               // NP (watts)
    var maxPower: Int?                      // Max power (watts)
    var powerBalance: Double?               // Left/right balance (if available)

    // MARK: - Pace Data (Running/Swimming)
    var averagePaceSecondsPerKm: Double?    // Average pace
    var normalizedPace: Double?             // NGP (grade-adjusted)
    var bestPaceSecondsPerKm: Double?       // Best pace segment

    // MARK: - Heart Rate Data
    var averageHeartRate: Int?
    var maxHeartRate: Int?
    var minHeartRate: Int?
    var heartRateZoneDistribution: [String: Double]?  // Time in each zone

    // MARK: - Cadence Data
    var averageCadence: Int?                // Steps/min or RPM
    var maxCadence: Int?

    // MARK: - Running Metrics
    var totalAscent: Double?                // Elevation gain (meters)
    var totalDescent: Double?               // Elevation loss (meters)
    var strideLength: Double?               // Average stride (meters)
    var verticalOscillation: Double?        // Vertical movement (cm)
    var groundContactTime: Double?          // Ground contact (ms)

    // MARK: - Swimming Metrics
    var poolLength: Double?                 // Pool length (meters)
    var swimStrokes: Int?                   // Total strokes
    var swolf: Int?                         // Swim efficiency score
    var laps: Int?                          // Number of laps

    // MARK: - Energy
    var activeCalories: Double?
    var totalCalories: Double?

    // MARK: - Environmental
    var weatherConditions: String?
    var temperature: Double?                // Celsius
    var humidity: Double?                   // Percentage

    // MARK: - Source & Notes
    var sourceDevice: String?               // "Apple Watch", "Garmin", etc.
    var notes: String?
    var indoorWorkout: Bool

    // MARK: - TrainingPeaks-specific Fields
    var powerZoneDistribution: [String: Double]?  // PWRZone1-10 minutes in each zone
    var rpe: Int?                                  // Rate of Perceived Exertion (1-10 scale)
    var feeling: Int?                              // How athlete felt (1-10 scale)
    var coachComments: String?                     // Coach's notes/comments
    var sourceRaw: String?                         // WorkoutSource raw value

    /// Source of the workout data
    var source: WorkoutSource {
        get { WorkoutSource(rawValue: sourceRaw ?? "") ?? .healthKit }
        set { sourceRaw = newValue.rawValue }
    }

    // MARK: - GPS Route
    var hasRoute: Bool
    var routeFileURL: String?               // Path to stored GPX/route data
    var routeData: Data?                    // Encoded polyline coordinates (JSON array of [lat, lng] pairs)

    init(
        id: UUID = UUID(),
        healthKitUUID: UUID? = nil,
        activityType: String,
        activityCategory: ActivityCategory = .other,
        title: String? = nil,
        startDate: Date,
        endDate: Date,
        durationSeconds: Double,
        distanceMeters: Double? = nil,
        tss: Double = 0,
        tssType: TSSType = .estimated,
        intensityFactor: Double = 0,
        indoorWorkout: Bool = false,
        hasRoute: Bool = false
    ) {
        self.id = id
        self.healthKitUUID = healthKitUUID
        self.createdAt = Date()
        self.updatedAt = Date()
        self.activityType = activityType
        self.activityCategoryRaw = activityCategory.rawValue
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.durationSeconds = durationSeconds
        self.distanceMeters = distanceMeters
        self.tss = tss
        self.tssTypeRaw = tssType.rawValue
        self.intensityFactor = intensityFactor
        self.indoorWorkout = indoorWorkout
        self.hasRoute = hasRoute
    }

    // MARK: - Computed Properties

    /// Duration formatted as H:MM:SS or M:SS
    var durationFormatted: String {
        let hours = Int(durationSeconds) / 3600
        let minutes = (Int(durationSeconds) % 3600) / 60
        let seconds = Int(durationSeconds) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Distance in kilometers
    var distanceKm: Double? {
        guard let meters = distanceMeters else { return nil }
        return meters / 1000
    }

    /// Distance in miles
    var distanceMiles: Double? {
        guard let meters = distanceMeters else { return nil }
        return meters / 1609.34
    }

    /// Distance formatted with unit
    var distanceFormatted: String? {
        guard let km = distanceKm else { return nil }
        if km >= 1 {
            return String(format: "%.2f km", km)
        }
        return String(format: "%.0f m", distanceMeters ?? 0)
    }

    /// Average pace formatted as M:SS /km
    var averagePaceFormatted: String? {
        guard let pace = averagePaceSecondsPerKm else { return nil }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    /// Average pace per mile formatted
    var averagePaceMileFormatted: String? {
        guard let paceKm = averagePaceSecondsPerKm else { return nil }
        let paceMile = paceKm * 1.60934
        let minutes = Int(paceMile) / 60
        let seconds = Int(paceMile) % 60
        return String(format: "%d:%02d /mi", minutes, seconds)
    }

    /// TSS per hour (intensity indicator)
    var tssPerHour: Double {
        guard durationSeconds > 0 else { return 0 }
        return tss / (durationSeconds / 3600)
    }

    /// Workout intensity level description
    var intensityLevel: String {
        switch intensityFactor {
        case 1.05...: return "All Out"
        case 0.95..<1.05: return "Threshold"
        case 0.85..<0.95: return "Tempo"
        case 0.75..<0.85: return "Endurance"
        default: return "Recovery"
        }
    }

    /// Day of week for the workout
    var dayOfWeek: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: startDate)
    }

    /// Short date string
    var dateFormatted: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: startDate)
    }

    /// Time of day
    var timeFormatted: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: startDate)
    }

    /// Icon for the activity
    var activityIcon: String {
        activityCategory.icon
    }

    /// Decoded GPS route coordinates from stored routeData
    var routeCoordinates: [CLLocationCoordinate2D]? {
        guard let data = routeData,
              let coords = try? JSONDecoder().decode([[Double]].self, from: data),
              !coords.isEmpty else { return nil }
        return coords.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[0], longitude: pair[1])
        }
    }

    /// Encode route coordinates as JSON data for storage
    static func encodeRoute(_ coordinates: [(latitude: Double, longitude: Double)]) -> Data? {
        let pairs = coordinates.map { [$0.latitude, $0.longitude] }
        return try? JSONEncoder().encode(pairs)
    }
}

// MARK: - Heart Rate Zone Analysis

extension WorkoutRecord {
    /// Calculate percentage of time in each HR zone
    func zonePercentages() -> [(zone: HeartRateZone, percentage: Double)] {
        guard let distribution = heartRateZoneDistribution else { return [] }

        return HeartRateZone.allCases.compactMap { zone in
            guard let time = distribution["zone\(zone.rawValue)"] else { return nil }
            let percentage = time / durationSeconds * 100
            return (zone, percentage)
        }
    }
}
