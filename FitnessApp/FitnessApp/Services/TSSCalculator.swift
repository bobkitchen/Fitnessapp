import Foundation
import HealthKit

/// Calculates Training Stress Score (TSS) for various workout types
/// TSS quantifies training load on a 0-∞ scale, where 100 = 1 hour at threshold
struct TSSCalculator {

    // MARK: - Power-Based TSS (Cycling)

    /// Calculate TSS from cycling power data
    /// TSS = (duration_seconds × NP × IF) / (FTP × 3600) × 100
    ///
    /// - Parameters:
    ///   - normalizedPower: NP in watts
    ///   - durationSeconds: Workout duration in seconds
    ///   - ftp: Functional Threshold Power in watts
    /// - Returns: TSS value
    static func calculatePowerTSS(
        normalizedPower: Int,
        durationSeconds: Double,
        ftp: Int
    ) -> TSSResult {
        guard ftp > 0, durationSeconds > 0 else {
            return TSSResult(tss: 0, type: .power, intensityFactor: 0)
        }

        let intensityFactor = Double(normalizedPower) / Double(ftp)
        let tss = (durationSeconds * Double(normalizedPower) * intensityFactor) / (Double(ftp) * 3600) * 100

        return TSSResult(
            tss: tss,
            type: .power,
            intensityFactor: intensityFactor,
            normalizedPower: normalizedPower
        )
    }

    /// Calculate TSS from raw power samples
    static func calculatePowerTSS(
        from powerSamples: [HKQuantitySample],
        durationSeconds: Double,
        ftp: Int
    ) -> TSSResult {
        guard let np = NormalizedPowerCalculator.calculateNormalizedPower(from: powerSamples) else {
            // Fall back to average power if NP can't be calculated
            let avgPower = powerSamples.reduce(0.0) { sum, sample in
                sum + sample.quantity.doubleValue(for: .watt())
            } / Double(max(1, powerSamples.count))

            return calculatePowerTSS(
                normalizedPower: Int(avgPower),
                durationSeconds: durationSeconds,
                ftp: ftp
            )
        }

        return calculatePowerTSS(
            normalizedPower: np,
            durationSeconds: durationSeconds,
            ftp: ftp
        )
    }

    // MARK: - Running TSS (rTSS)

    /// Calculate running TSS from pace data
    /// rTSS = (duration_seconds × NGP × IF) / (threshold_pace × 3600) × 100
    ///
    /// - Parameters:
    ///   - normalizedGradedPace: NGP in seconds per km
    ///   - durationSeconds: Workout duration
    ///   - thresholdPace: Threshold pace in seconds per km
    /// - Returns: rTSS value
    static func calculateRunningTSS(
        normalizedGradedPace: Double,
        durationSeconds: Double,
        thresholdPace: Double
    ) -> TSSResult {
        guard thresholdPace > 0, durationSeconds > 0, normalizedGradedPace > 0 else {
            return TSSResult(tss: 0, type: .pace, intensityFactor: 0)
        }

        // For pace, faster = harder, so IF = threshold / actual
        let intensityFactor = thresholdPace / normalizedGradedPace

        // rTSS formula - intensity squared times duration
        let tss = (durationSeconds / 3600) * pow(intensityFactor, 2) * 100

        return TSSResult(
            tss: tss,
            type: .pace,
            intensityFactor: intensityFactor,
            normalizedPace: normalizedGradedPace
        )
    }

    /// Calculate running TSS from workout with basic metrics
    static func calculateRunningTSS(
        averagePace: Double,       // sec/km
        durationSeconds: Double,
        thresholdPace: Double,     // sec/km
        totalAscent: Double?,      // meters
        totalDescent: Double?,     // meters
        distance: Double?          // meters
    ) -> TSSResult {
        // Try to calculate NGP if elevation data is available
        var ngp = averagePace

        if let ascent = totalAscent,
           let descent = totalDescent,
           let dist = distance,
           dist > 0 {
            if let calculatedNGP = NormalizedPowerCalculator.calculateNormalizedGradedPace(
                pace: averagePace,
                duration: durationSeconds,
                totalAscent: ascent,
                totalDescent: descent,
                distance: dist
            ) {
                ngp = calculatedNGP
            }
        }

        return calculateRunningTSS(
            normalizedGradedPace: ngp,
            durationSeconds: durationSeconds,
            thresholdPace: thresholdPace
        )
    }

    // MARK: - Running Power TSS

    /// Calculate TSS from running power (similar to cycling but with running-specific NP)
    static func calculateRunningPowerTSS(
        normalizedPower: Int,
        durationSeconds: Double,
        runningFTP: Int
    ) -> TSSResult {
        guard runningFTP > 0, durationSeconds > 0 else {
            return TSSResult(tss: 0, type: .runningPower, intensityFactor: 0)
        }

        let intensityFactor = Double(normalizedPower) / Double(runningFTP)
        let tss = (durationSeconds * Double(normalizedPower) * intensityFactor) / (Double(runningFTP) * 3600) * 100

        return TSSResult(
            tss: tss,
            type: .runningPower,
            intensityFactor: intensityFactor,
            normalizedPower: normalizedPower
        )
    }

    // MARK: - Heart Rate TSS (hrTSS)

    /// Calculate TSS from heart rate when power/pace data not available
    /// Uses zone-based TSS/hour factors
    ///
    /// - Parameters:
    ///   - heartRateSamples: HR samples from workout
    ///   - durationSeconds: Workout duration
    ///   - thresholdHR: Lactate threshold heart rate
    ///   - maxHR: Maximum heart rate
    /// - Returns: hrTSS value
    static func calculateHeartRateTSS(
        heartRateSamples: [HKQuantitySample],
        durationSeconds: Double,
        thresholdHR: Int,
        maxHR: Int
    ) -> TSSResult {
        guard !heartRateSamples.isEmpty, thresholdHR > 0 else {
            return TSSResult(tss: 0, type: .heartRate, intensityFactor: 0)
        }

        // Calculate time in each zone
        var zoneSeconds: [HeartRateZone: Double] = [:]
        for zone in HeartRateZone.allCases {
            zoneSeconds[zone] = 0
        }

        var lastTimestamp: Date?
        var lastZone: HeartRateZone?

        for sample in heartRateSamples.sorted(by: { $0.startDate < $1.startDate }) {
            let hr = Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            let zone = determineHeartRateZone(hr: hr, thresholdHR: thresholdHR)

            if let lastTime = lastTimestamp, let prevZone = lastZone {
                let interval = sample.startDate.timeIntervalSince(lastTime)
                zoneSeconds[prevZone, default: 0] += interval
            }

            lastTimestamp = sample.startDate
            lastZone = zone
        }

        // Handle last interval
        if let lastTime = lastTimestamp, let lastZ = lastZone {
            let remainingTime = durationSeconds - heartRateSamples.first!.startDate.distance(to: lastTime)
            if remainingTime > 0 {
                zoneSeconds[lastZ, default: 0] += remainingTime
            }
        }

        // Calculate weighted TSS from zone time
        var tss = 0.0
        for (zone, seconds) in zoneSeconds {
            let hours = seconds / 3600
            tss += hours * zone.tssPerHour
        }

        // Calculate average IF from HR data
        let avgHR = heartRateSamples.reduce(0.0) { sum, sample in
            sum + sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        } / Double(heartRateSamples.count)

        let intensityFactor = avgHR / Double(thresholdHR)

        return TSSResult(
            tss: tss,
            type: .heartRate,
            intensityFactor: intensityFactor,
            averageHeartRate: Int(avgHR)
        )
    }

    /// Calculate hrTSS from average heart rate using TRIMP-based formula
    /// This matches TrainingPeaks hrTSS calculation more closely
    /// hrTSS = (duration/3600) × HRIF² × 100
    static func calculateHeartRateTSS(
        averageHR: Int,
        durationSeconds: Double,
        thresholdHR: Int
    ) -> TSSResult {
        guard thresholdHR > 0, averageHR > 0 else {
            return TSSResult(tss: 0, type: .heartRate, intensityFactor: 0)
        }

        // Heart rate intensity factor (similar to IF for power)
        let hrIF = Double(averageHR) / Double(thresholdHR)

        // TSS formula: hours × IF² × 100
        // This gives TSS = 100 for 1 hour at threshold HR
        let hours = durationSeconds / 3600
        let tss = hours * pow(hrIF, 2) * 100

        return TSSResult(
            tss: tss,
            type: .heartRate,
            intensityFactor: hrIF,
            averageHeartRate: averageHR
        )
    }

    // MARK: - Swimming TSS

    /// Calculate swimming TSS based on pace and intensity
    static func calculateSwimTSS(
        averagePacePer100m: Double,   // seconds per 100m
        durationSeconds: Double,
        thresholdPacePer100m: Double
    ) -> TSSResult {
        guard thresholdPacePer100m > 0, durationSeconds > 0 else {
            return TSSResult(tss: 0, type: .swim, intensityFactor: 0)
        }

        // Similar to running - faster pace = higher IF
        let intensityFactor = thresholdPacePer100m / averagePacePer100m
        let tss = (durationSeconds / 3600) * pow(intensityFactor, 2) * 100

        return TSSResult(
            tss: tss,
            type: .swim,
            intensityFactor: intensityFactor
        )
    }

    // MARK: - Generic/Estimated TSS

    /// Estimate TSS when no detailed data is available
    /// Uses perceived intensity and duration
    static func estimateTSS(
        durationSeconds: Double,
        perceivedIntensity: Double  // 0-1 scale
    ) -> TSSResult {
        // Map perceived intensity to approximate IF
        // Easy: 0.6, Moderate: 0.75, Hard: 0.9, All-out: 1.05
        let intensityFactor = 0.5 + (perceivedIntensity * 0.6)
        let tss = (durationSeconds / 3600) * pow(intensityFactor, 2) * 100

        return TSSResult(
            tss: tss,
            type: .estimated,
            intensityFactor: intensityFactor
        )
    }

    // MARK: - Helper Methods

    private static func determineHeartRateZone(hr: Int, thresholdHR: Int) -> HeartRateZone {
        let percentage = Double(hr) / Double(thresholdHR)

        for zone in HeartRateZone.allCases {
            if zone.hrPercentRange.contains(percentage) {
                return zone
            }
        }

        return percentage < 0.81 ? .zone1 : .zone5
    }

    // MARK: - Auto-detect Best TSS Method

    /// Automatically calculate TSS using the best available data
    static func calculateBestTSS(
        workout: HKWorkout,
        powerSamples: [HKQuantitySample]?,
        heartRateSamples: [HKQuantitySample]?,
        profile: AthleteProfile
    ) -> TSSResult {
        let duration = workout.duration
        let activityType = workout.workoutActivityType

        // Cycling with power data
        if activityType == .cycling,
           let samples = powerSamples, !samples.isEmpty,
           let ftp = profile.ftpWatts {
            return calculatePowerTSS(from: samples, durationSeconds: duration, ftp: ftp)
        }

        // Running with power data
        if (activityType == .running || activityType == .walking),
           let samples = powerSamples, !samples.isEmpty,
           let runningFTP = profile.runningFTPWatts {
            if let np = NormalizedPowerCalculator.calculateNormalizedPower(from: samples) {
                return calculateRunningPowerTSS(normalizedPower: np, durationSeconds: duration, runningFTP: runningFTP)
            }
        }

        // Running with pace data
        if activityType == .running,
           let thresholdPace = profile.thresholdPaceSecondsPerKm {
            let distance = workout.totalDistance?.doubleValue(for: .meter())
            let avgPace = distance.map { duration / ($0 / 1000) } ?? thresholdPace

            // Get elevation if available from workout metadata
            let ascent = workout.metadata?[HKMetadataKeyElevationAscended] as? Double
            let descent = workout.metadata?[HKMetadataKeyElevationDescended] as? Double

            return calculateRunningTSS(
                averagePace: avgPace,
                durationSeconds: duration,
                thresholdPace: thresholdPace,
                totalAscent: ascent,
                totalDescent: descent,
                distance: distance
            )
        }

        // Swimming
        if activityType == .swimming,
           let thresholdSwimPace = profile.swimThresholdPacePer100m {
            let distance = workout.totalDistance?.doubleValue(for: .meter()) ?? 0
            let avgPace = distance > 0 ? duration / (distance / 100) : thresholdSwimPace

            return calculateSwimTSS(
                averagePacePer100m: avgPace,
                durationSeconds: duration,
                thresholdPacePer100m: thresholdSwimPace
            )
        }

        // Fall back to heart rate
        if let hrSamples = heartRateSamples, !hrSamples.isEmpty {
            return calculateHeartRateTSS(
                heartRateSamples: hrSamples,
                durationSeconds: duration,
                thresholdHR: profile.thresholdHeartRate,
                maxHR: profile.maxHeartRate
            )
        }

        // Last resort: estimate based on duration and activity type
        let estimatedIntensity: Double
        switch activityType {
        case .running: estimatedIntensity = 0.7
        case .cycling: estimatedIntensity = 0.65
        case .swimming: estimatedIntensity = 0.7
        case .functionalStrengthTraining, .traditionalStrengthTraining: estimatedIntensity = 0.6
        case .highIntensityIntervalTraining: estimatedIntensity = 0.85
        case .yoga, .flexibility: estimatedIntensity = 0.3
        default: estimatedIntensity = 0.5
        }

        return estimateTSS(durationSeconds: duration, perceivedIntensity: estimatedIntensity)
    }
}

// MARK: - TSS Result

struct TSSResult {
    var tss: Double
    let type: TSSType
    let intensityFactor: Double
    var normalizedPower: Int?
    var normalizedPace: Double?
    var averageHeartRate: Int?

    /// Whether a scaling factor was applied
    var scalingApplied: Bool = false

    /// The scaling factor that was applied (if any)
    var appliedScalingFactor: Double?

    /// Original TSS before scaling (if scaled)
    var originalTSS: Double?

    /// TSS per hour - useful for comparing workout intensities
    var tssPerHour: Double {
        // This would need duration to calculate, using IF as proxy
        return pow(intensityFactor, 2) * 100
    }

    /// Intensity level description
    var intensityDescription: String {
        switch intensityFactor {
        case 1.05...: return "All Out"
        case 0.95..<1.05: return "Threshold"
        case 0.85..<0.95: return "Tempo"
        case 0.75..<0.85: return "Endurance"
        case 0.55..<0.75: return "Recovery"
        default: return "Easy"
        }
    }

    /// Apply a scaling factor to this result
    mutating func applyScaling(factor: Double) {
        guard !scalingApplied else { return }
        originalTSS = tss
        tss *= factor
        scalingApplied = true
        appliedScalingFactor = factor
    }
}

// MARK: - Scaled TSS Calculation

extension TSSCalculator {

    /// Calculate TSS with learned scaling applied
    /// - Parameters:
    ///   - workout: The HKWorkout to calculate TSS for
    ///   - powerSamples: Power data samples (if available)
    ///   - heartRateSamples: Heart rate samples (if available)
    ///   - profile: Athlete profile with threshold values
    ///   - scalingProfile: Learned TSS scaling profile
    /// - Returns: TSSResult with scaling applied if appropriate
    static func calculateScaledTSS(
        workout: HKWorkout,
        powerSamples: [HKQuantitySample]?,
        heartRateSamples: [HKQuantitySample]?,
        profile: AthleteProfile,
        scalingProfile: TSSScalingProfile?
    ) -> TSSResult {
        // First calculate base TSS
        var result = calculateBestTSS(
            workout: workout,
            powerSamples: powerSamples,
            heartRateSamples: heartRateSamples,
            profile: profile
        )

        // Apply scaling if we have a valid profile
        if let scaling = scalingProfile, scaling.canApplyScaling {
            // Determine activity category
            let category = activityCategory(for: workout.workoutActivityType)
            let scalingFactor = scaling.scalingFactor(for: category)

            // Apply the scaling
            result.applyScaling(factor: scalingFactor)
        }

        return result
    }

    /// Calculate TSS for a workout using category-specific scaling
    /// Simplified version that takes calculated category directly
    static func calculateScaledTSS(
        baseTSS: Double,
        type: TSSType,
        intensityFactor: Double,
        category: ActivityCategory,
        scalingProfile: TSSScalingProfile?
    ) -> TSSResult {
        var result = TSSResult(
            tss: baseTSS,
            type: type,
            intensityFactor: intensityFactor
        )

        // Apply scaling if available and valid
        if let scaling = scalingProfile, scaling.canApplyScaling {
            let scalingFactor = scaling.scalingFactor(for: category)
            result.applyScaling(factor: scalingFactor)
        }

        return result
    }

    /// Helper to determine activity category from workout type
    private static func activityCategory(for type: HKWorkoutActivityType) -> ActivityCategory {
        switch type {
        case .running, .walking, .hiking: return .run
        case .cycling: return .bike
        case .swimming: return .swim
        case .functionalStrengthTraining, .traditionalStrengthTraining, .coreTraining: return .strength
        default: return .other
        }
    }
}
