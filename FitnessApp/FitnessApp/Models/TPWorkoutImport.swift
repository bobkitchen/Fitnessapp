import Foundation

/// Represents a workout imported from a TrainingPeaks CSV export
struct TPWorkoutImport: Codable, Sendable {
    let title: String?
    let workoutType: String
    let workoutDay: Date
    let distanceMeters: Double?
    let durationSeconds: Double?
    let powerAverage: Int?
    let powerMax: Int?
    let powerNormalized: Int?
    let heartRateAverage: Int?
    let heartRateMax: Int?
    let cadenceAverage: Int?
    let intensityFactor: Double?
    let tss: Double?
    let velocityAverage: Double?
    let velocityMax: Double?
    let calories: Double?
    let elevationGain: Double?
    let elevationLoss: Double?

    // Zone data (minutes in each zone, 1-10)
    let hrZones: [Double]      // HRZone1-10
    let powerZones: [Double]   // PWRZone1-10

    // Subjective data
    let rpe: Int?              // Rate of Perceived Exertion (1-10)
    let feeling: Int?          // How the athlete felt (1-10)
    let athleteComments: String?
    let coachComments: String?

    /// Map TP workout type to our ActivityCategory
    var activityCategory: ActivityCategory {
        let type = workoutType.lowercased()

        if type.contains("cycling") || type.contains("bike") || type.contains("biking") || type.contains("ride") {
            return .bike
        } else if type.contains("running") || type.contains("run") || type.contains("treadmill") {
            return .run
        } else if type.contains("swim") || type.contains("pool") || type.contains("open water") {
            return .swim
        } else if type.contains("strength") || type.contains("weight") || type.contains("gym") || type.contains("core") {
            return .strength
        }
        return .other
    }

    /// Calculate total HR zone time in minutes
    var totalHRZoneMinutes: Double {
        hrZones.reduce(0, +)
    }

    /// Calculate total power zone time in minutes
    var totalPowerZoneMinutes: Double {
        powerZones.reduce(0, +)
    }

    /// HR zone distribution as percentages
    var hrZonePercentages: [String: Double] {
        let total = totalHRZoneMinutes
        guard total > 0 else { return [:] }

        var distribution: [String: Double] = [:]
        for (index, minutes) in hrZones.enumerated() {
            distribution["zone\(index + 1)"] = (minutes / total) * 100
        }
        return distribution
    }

    /// Power zone distribution as percentages
    var powerZonePercentages: [String: Double] {
        let total = totalPowerZoneMinutes
        guard total > 0 else { return [:] }

        var distribution: [String: Double] = [:]
        for (index, minutes) in powerZones.enumerated() {
            distribution["zone\(index + 1)"] = (minutes / total) * 100
        }
        return distribution
    }
}

// MARK: - CSV Column Mapping

extension TPWorkoutImport {
    /// Maps TrainingPeaks CSV column names to struct properties
    enum CSVColumn: String, CaseIterable {
        // Basic info
        case title = "Title"
        case workoutType = "WorkoutType"
        case workoutDay = "WorkoutDay"

        // Duration and distance
        case timeTotalInHours = "TimeTotalInHours"
        case distanceInMeters = "DistanceInMeters"

        // Power metrics
        case powerAverage = "PowerAverage"
        case powerMax = "PowerMax"
        case normalizedPower = "NormalizedPower"

        // Heart rate metrics
        case heartRateAverage = "HeartRateAverage"
        case heartRateMax = "HeartRateMax"

        // Cadence
        case cadenceAverage = "CadenceAverage"

        // TSS and IF
        case tss = "TSS"
        case intensityFactor = "IF"

        // Velocity
        case velocityAverage = "VelocityAverage"
        case velocityMax = "VelocityMax"

        // Other metrics
        case calories = "Calories"
        case elevationGain = "ElevationGain"
        case elevationLoss = "ElevationLoss"

        // HR Zones (minutes)
        case hrZone1 = "HRZone1"
        case hrZone2 = "HRZone2"
        case hrZone3 = "HRZone3"
        case hrZone4 = "HRZone4"
        case hrZone5 = "HRZone5"
        case hrZone6 = "HRZone6"
        case hrZone7 = "HRZone7"
        case hrZone8 = "HRZone8"
        case hrZone9 = "HRZone9"
        case hrZone10 = "HRZone10"

        // Power Zones (minutes)
        case pwrZone1 = "PWRZone1"
        case pwrZone2 = "PWRZone2"
        case pwrZone3 = "PWRZone3"
        case pwrZone4 = "PWRZone4"
        case pwrZone5 = "PWRZone5"
        case pwrZone6 = "PWRZone6"
        case pwrZone7 = "PWRZone7"
        case pwrZone8 = "PWRZone8"
        case pwrZone9 = "PWRZone9"
        case pwrZone10 = "PWRZone10"

        // Subjective data
        case rpe = "Rpe"
        case feeling = "Feeling"
        case athleteComments = "AthleteComment"
        case coachComments = "CoachComment"
    }

    /// Create a TPWorkoutImport from a CSV row dictionary
    static func from(csvRow: [String: String], dateFormatter: DateFormatter) -> TPWorkoutImport? {
        // Required field: WorkoutDay
        guard let dateString = csvRow[CSVColumn.workoutDay.rawValue],
              let workoutDay = dateFormatter.date(from: dateString) else {
            return nil
        }

        // Validate year is reasonable (not year 1 or year 0001)
        let year = Calendar.current.component(.year, from: workoutDay)
        if year < 1900 || year > 2100 {
            print("[TPWorkoutImport] Invalid year \(year) parsed from '\(dateString)'")
            return nil
        }

        // Required field: WorkoutType
        guard let workoutType = csvRow[CSVColumn.workoutType.rawValue], !workoutType.isEmpty else {
            return nil
        }

        // Parse optional numeric fields
        let durationHours = Double(csvRow[CSVColumn.timeTotalInHours.rawValue] ?? "")
        let durationSeconds = durationHours.map { $0 * 3600 }

        // Parse HR zones
        let hrZones: [Double] = [
            Double(csvRow[CSVColumn.hrZone1.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.hrZone2.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.hrZone3.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.hrZone4.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.hrZone5.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.hrZone6.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.hrZone7.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.hrZone8.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.hrZone9.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.hrZone10.rawValue] ?? "") ?? 0
        ]

        // Parse power zones
        let powerZones: [Double] = [
            Double(csvRow[CSVColumn.pwrZone1.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.pwrZone2.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.pwrZone3.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.pwrZone4.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.pwrZone5.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.pwrZone6.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.pwrZone7.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.pwrZone8.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.pwrZone9.rawValue] ?? "") ?? 0,
            Double(csvRow[CSVColumn.pwrZone10.rawValue] ?? "") ?? 0
        ]

        return TPWorkoutImport(
            title: csvRow[CSVColumn.title.rawValue],
            workoutType: workoutType,
            workoutDay: workoutDay,
            distanceMeters: Double(csvRow[CSVColumn.distanceInMeters.rawValue] ?? ""),
            durationSeconds: durationSeconds,
            powerAverage: Int(csvRow[CSVColumn.powerAverage.rawValue] ?? ""),
            powerMax: Int(csvRow[CSVColumn.powerMax.rawValue] ?? ""),
            powerNormalized: Int(csvRow[CSVColumn.normalizedPower.rawValue] ?? ""),
            heartRateAverage: Int(csvRow[CSVColumn.heartRateAverage.rawValue] ?? ""),
            heartRateMax: Int(csvRow[CSVColumn.heartRateMax.rawValue] ?? ""),
            cadenceAverage: Int(csvRow[CSVColumn.cadenceAverage.rawValue] ?? ""),
            intensityFactor: Double(csvRow[CSVColumn.intensityFactor.rawValue] ?? ""),
            tss: Double(csvRow[CSVColumn.tss.rawValue] ?? ""),
            velocityAverage: Double(csvRow[CSVColumn.velocityAverage.rawValue] ?? ""),
            velocityMax: Double(csvRow[CSVColumn.velocityMax.rawValue] ?? ""),
            calories: Double(csvRow[CSVColumn.calories.rawValue] ?? ""),
            elevationGain: Double(csvRow[CSVColumn.elevationGain.rawValue] ?? ""),
            elevationLoss: Double(csvRow[CSVColumn.elevationLoss.rawValue] ?? ""),
            hrZones: hrZones,
            powerZones: powerZones,
            rpe: Int(csvRow[CSVColumn.rpe.rawValue] ?? ""),
            feeling: Int(csvRow[CSVColumn.feeling.rawValue] ?? ""),
            athleteComments: csvRow[CSVColumn.athleteComments.rawValue],
            coachComments: csvRow[CSVColumn.coachComments.rawValue]
        )
    }
}
