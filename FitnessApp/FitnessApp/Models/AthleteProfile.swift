import Foundation
import SwiftData

@Model
final class AthleteProfile {
    var id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    // Cycling Thresholds
    var ftpWatts: Int?                      // Functional Threshold Power (cycling)

    // Running Thresholds
    var thresholdPaceSecondsPerKm: Double?  // Threshold pace (running)
    var runningFTPWatts: Int?               // Running FTP if using running power

    // Swimming Thresholds
    var swimThresholdPacePer100m: Double?   // Threshold pace for swimming (seconds per 100m)

    // Heart Rate Thresholds
    var thresholdHeartRate: Int             // LTHR - Lactate Threshold Heart Rate
    var maxHeartRate: Int                   // Maximum Heart Rate
    var restingHeartRate: Int               // Resting Heart Rate

    // Body Metrics
    var birthDate: Date?
    var weightKg: Double?
    var heightCm: Double?

    // Goals & Preferences
    var primarySport: String?               // "triathlon", "cycling", "running", etc.
    var weeklyTSSTarget: Double?            // Target weekly training load
    var preferredTrainingDays: [Int]?       // Days of week (1=Sunday, 7=Saturday)

    // Equipment flags
    var hasCyclingPowerMeter: Bool
    var hasRunningPowerMeter: Bool

    // Profile Photo
    var profilePhotoData: Data?

    init(
        id: UUID = UUID(),
        name: String = "",
        ftpWatts: Int? = nil,
        thresholdPaceSecondsPerKm: Double? = nil,
        runningFTPWatts: Int? = nil,
        swimThresholdPacePer100m: Double? = nil,
        thresholdHeartRate: Int = 165,
        maxHeartRate: Int = 185,
        restingHeartRate: Int = 50,
        birthDate: Date? = nil,
        weightKg: Double? = nil,
        heightCm: Double? = nil,
        primarySport: String? = "triathlon",
        weeklyTSSTarget: Double? = nil,
        preferredTrainingDays: [Int]? = nil,
        hasCyclingPowerMeter: Bool = true,
        hasRunningPowerMeter: Bool = true
    ) {
        self.id = id
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.ftpWatts = ftpWatts
        self.thresholdPaceSecondsPerKm = thresholdPaceSecondsPerKm
        self.runningFTPWatts = runningFTPWatts
        self.swimThresholdPacePer100m = swimThresholdPacePer100m
        self.thresholdHeartRate = thresholdHeartRate
        self.maxHeartRate = maxHeartRate
        self.restingHeartRate = restingHeartRate
        self.birthDate = birthDate
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.primarySport = primarySport
        self.weeklyTSSTarget = weeklyTSSTarget
        self.preferredTrainingDays = preferredTrainingDays
        self.hasCyclingPowerMeter = hasCyclingPowerMeter
        self.hasRunningPowerMeter = hasRunningPowerMeter
    }

    // MARK: - Computed Properties

    var age: Int? {
        guard let birthDate else { return nil }
        return Calendar.current.dateComponents([.year], from: birthDate, to: Date()).year
    }

    /// Threshold pace as min:sec per km string
    var thresholdPaceFormatted: String? {
        guard let pace = thresholdPaceSecondsPerKm else { return nil }
        let minutes = Int(pace) / 60
        let seconds = Int(pace) % 60
        return String(format: "%d:%02d /km", minutes, seconds)
    }

    /// Threshold pace as min:sec per mile string
    var thresholdPaceMileFormatted: String? {
        guard let pacePerKm = thresholdPaceSecondsPerKm else { return nil }
        let pacePerMile = pacePerKm * 1.60934
        let minutes = Int(pacePerMile) / 60
        let seconds = Int(pacePerMile) % 60
        return String(format: "%d:%02d /mi", minutes, seconds)
    }

    /// Estimated max HR if not set (220 - age formula as fallback)
    var estimatedMaxHR: Int {
        if let age {
            return 220 - age
        }
        return maxHeartRate
    }

    /// Heart rate reserve (HRR)
    var heartRateReserve: Int {
        maxHeartRate - restingHeartRate
    }

    /// Get initials for avatar placeholder (up to 2 characters)
    var initials: String {
        let components = name.trimmingCharacters(in: .whitespaces).split(separator: " ")
        if components.isEmpty {
            return ""
        } else if components.count == 1 {
            return String(components[0].prefix(1)).uppercased()
        } else {
            let first = String(components[0].prefix(1))
            let last = String(components[components.count - 1].prefix(1))
            return (first + last).uppercased()
        }
    }

    // MARK: - Heart Rate Zone Calculations

    /// Calculate heart rate zones based on threshold HR
    func heartRateZoneBoundaries() -> [(zone: HeartRateZone, minHR: Int, maxHR: Int)] {
        return HeartRateZone.allCases.map { zone in
            let minHR = Int(Double(thresholdHeartRate) * zone.hrPercentRange.lowerBound)
            let maxHR = Int(Double(thresholdHeartRate) * zone.hrPercentRange.upperBound)
            return (zone, minHR, maxHR)
        }
    }

    /// Determine HR zone for a given heart rate
    func heartRateZone(for heartRate: Int) -> HeartRateZone {
        let percentage = Double(heartRate) / Double(thresholdHeartRate)
        for zone in HeartRateZone.allCases {
            if zone.hrPercentRange.contains(percentage) {
                return zone
            }
        }
        return percentage < 0.81 ? .zone1 : .zone5
    }
}
