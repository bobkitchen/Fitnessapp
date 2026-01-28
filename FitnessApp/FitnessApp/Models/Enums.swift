import Foundation

/// Type of TSS calculation used for a workout
nonisolated enum TSSType: String, Codable, CaseIterable, Sendable {
    case power = "Power"           // Cycling power-based TSS
    case runningPower = "rPower"   // Running power-based TSS
    case pace = "Pace"             // Running pace-based rTSS
    case heartRate = "HR"          // Heart rate-based hrTSS
    case swim = "Swim"             // Swimming TSS
    case estimated = "Est"         // Estimated/default TSS
    case trainingPeaks = "TP"      // Pre-calculated by TrainingPeaks

    var description: String {
        switch self {
        case .power: return "Cycling power meter data"
        case .runningPower: return "Running power (Stryd/watch)"
        case .pace: return "Pace-based calculation"
        case .heartRate: return "Heart rate fallback"
        case .swim: return "Swim pace calculation"
        case .estimated: return "Duration estimate only"
        case .trainingPeaks: return "Pre-calculated by TrainingPeaks"
        }
    }

    var displayName: String {
        switch self {
        case .power: return "Power TSS"
        case .runningPower: return "Running Power"
        case .pace: return "Pace rTSS"
        case .heartRate: return "HR TSS"
        case .swim: return "Swim TSS"
        case .estimated: return "Estimated"
        case .trainingPeaks: return "TrainingPeaks"
        }
    }

    /// Quality indicator - power is most accurate, estimated is least
    var qualityRank: Int {
        switch self {
        case .trainingPeaks: return 4  // Highest - pre-calculated with full data
        case .power, .runningPower: return 3
        case .pace, .swim: return 2
        case .heartRate: return 1
        case .estimated: return 0
        }
    }
}

/// Source of metric data
nonisolated enum MetricSource: String, Codable, Sendable {
    case healthKit = "HealthKit"
    case manual = "Manual"
    case trainingPeaksCalibration = "TrainingPeaks"
    case calculated = "Calculated"
}

/// Source of workout data
nonisolated enum WorkoutSource: String, Codable, Sendable {
    case healthKit = "HealthKit"       // Synced from Apple Health
    case strava = "Strava"             // Synced from Strava
    case trainingPeaks = "TrainingPeaks" // Imported from TrainingPeaks CSV
    case manual = "Manual"             // Manually entered

    var displayName: String {
        switch self {
        case .healthKit: return "Apple Health"
        case .strava: return "Strava"
        case .trainingPeaks: return "TrainingPeaks"
        case .manual: return "Manual Entry"
        }
    }

    var icon: String {
        switch self {
        case .healthKit: return "heart.fill"
        case .strava: return "figure.run.circle"
        case .trainingPeaks: return "chart.line.uptrend.xyaxis"
        case .manual: return "pencil"
        }
    }
}

/// TSS verification status for quick-verify feature
nonisolated enum TSSVerificationStatus: String, Codable, Sendable {
    case pending = "pending"           // Not yet verified by user
    case confirmed = "confirmed"       // User confirmed calculated value matches TP
    case corrected = "corrected"       // User entered different value from TP

    var icon: String {
        switch self {
        case .pending: return "questionmark.circle"
        case .confirmed: return "checkmark.circle.fill"
        case .corrected: return "pencil.circle.fill"
        }
    }
}

/// Activity type categories
nonisolated enum ActivityCategory: String, Codable, CaseIterable, Sendable {
    case run = "Run"
    case bike = "Bike"
    case swim = "Swim"
    case strength = "Strength"
    case other = "Other"

    var icon: String {
        switch self {
        case .run: return "figure.run"
        case .bike: return "bicycle"
        case .swim: return "figure.pool.swim"
        case .strength: return "dumbbell"
        case .other: return "figure.mixed.cardio"
        }
    }
}

/// Training readiness levels based on composite wellness score
nonisolated enum TrainingReadiness: String, Codable, CaseIterable, Sendable {
    case fullyReady = "Fully Ready"
    case mostlyReady = "Mostly Ready"
    case reducedCapacity = "Reduced Capacity"
    case restRecommended = "Rest Recommended"

    init(score: Double) {
        switch score {
        case 80...100: self = .fullyReady
        case 60..<80: self = .mostlyReady
        case 40..<60: self = .reducedCapacity
        default: self = .restRecommended
        }
    }

    var description: String {
        switch self {
        case .fullyReady: return "Go hard - your body is ready for intense training"
        case .mostlyReady: return "Normal training - proceed as planned"
        case .reducedCapacity: return "Easy/recovery - consider lighter intensity"
        case .restRecommended: return "Take a rest day - recovery needed"
        }
    }

    var color: String {
        switch self {
        case .fullyReady: return "green"
        case .mostlyReady: return "blue"
        case .reducedCapacity: return "orange"
        case .restRecommended: return "red"
        }
    }

    var scoreRange: ClosedRange<Double> {
        switch self {
        case .fullyReady: return 80...100
        case .mostlyReady: return 60...79
        case .reducedCapacity: return 40...59
        case .restRecommended: return 0...39
        }
    }
}

/// Heart rate training zones
nonisolated enum HeartRateZone: Int, Codable, CaseIterable, Sendable {
    case zone1 = 1  // Recovery
    case zone2 = 2  // Endurance
    case zone3 = 3  // Tempo
    case zone4 = 4  // Threshold
    case zone5 = 5  // VO2max

    var name: String {
        switch self {
        case .zone1: return "Recovery"
        case .zone2: return "Endurance"
        case .zone3: return "Tempo"
        case .zone4: return "Threshold"
        case .zone5: return "VO2max"
        }
    }

    /// TSS per hour for this zone
    var tssPerHour: Double {
        switch self {
        case .zone1: return 30
        case .zone2: return 50
        case .zone3: return 70
        case .zone4: return 90
        case .zone5: return 110
        }
    }

    /// Percentage of threshold HR for zone boundaries
    var hrPercentRange: ClosedRange<Double> {
        switch self {
        case .zone1: return 0...0.81
        case .zone2: return 0.81...0.89
        case .zone3: return 0.89...0.93
        case .zone4: return 0.93...0.99
        case .zone5: return 0.99...1.10
        }
    }
}

/// Trend direction for metrics
nonisolated enum Trend: String, Codable, Sendable {
    case up = "up"
    case down = "down"
    case stable = "stable"

    var icon: String {
        switch self {
        case .up: return "arrow.up.right"
        case .down: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }

    var displayName: String {
        switch self {
        case .up: return "Improving"
        case .down: return "Declining"
        case .stable: return "Stable"
        }
    }
}

/// Sleep stage types from HealthKit
nonisolated enum SleepStage: String, Codable, Sendable {
    case awake = "Awake"
    case rem = "REM"
    case core = "Core"
    case deep = "Deep"
    case inBed = "In Bed"
    case asleep = "Asleep"  // Generic asleep (older data)
}

/// Date range options for charts
nonisolated enum ChartDateRange: String, CaseIterable, Sendable {
    case week = "7D"
    case month = "30D"
    case quarter = "90D"
    case year = "1Y"
    case all = "All"

    var days: Int? {
        switch self {
        case .week: return 7
        case .month: return 30
        case .quarter: return 90
        case .year: return 365
        case .all: return nil
        }
    }
}
