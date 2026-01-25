import Foundation
import HealthKit

/// Calculates Normalized Power (NP) and Normalized Graded Pace (NGP)
/// These are smoothed metrics that better represent physiological cost
struct NormalizedPowerCalculator {

    // MARK: - Normalized Power (Cycling)

    /// Calculate Normalized Power from power samples
    /// NP = 4th root of average of (30-second rolling average)^4
    ///
    /// - Parameters:
    ///   - samples: Power samples from HealthKit
    ///   - rollingWindowSeconds: Rolling average window (default 30s)
    /// - Returns: Normalized Power in watts
    static func calculateNormalizedPower(
        from samples: [HKQuantitySample],
        rollingWindowSeconds: Int = 30
    ) -> Int? {
        guard samples.count > rollingWindowSeconds else { return nil }

        // Convert to power values with timestamps
        let powerData = samples.map { sample -> (timestamp: Date, power: Double) in
            let power = sample.quantity.doubleValue(for: .watt())
            return (sample.startDate, power)
        }

        // Resample to 1-second intervals
        let resampledPower = resampleToOneSecond(powerData)
        guard resampledPower.count > rollingWindowSeconds else { return nil }

        // Calculate 30-second rolling averages
        var rollingAverages: [Double] = []
        for i in (rollingWindowSeconds - 1)..<resampledPower.count {
            let window = resampledPower[(i - rollingWindowSeconds + 1)...i]
            let avg = window.reduce(0, +) / Double(rollingWindowSeconds)
            rollingAverages.append(avg)
        }

        // Calculate 4th power of each rolling average
        let fourthPowers = rollingAverages.map { pow($0, 4) }

        // Average of 4th powers
        let avgFourthPower = fourthPowers.reduce(0, +) / Double(fourthPowers.count)

        // 4th root to get NP
        let normalizedPower = pow(avgFourthPower, 0.25)

        return Int(normalizedPower)
    }

    /// Calculate Normalized Power from raw power values at 1-second intervals
    static func calculateNormalizedPower(
        from powerValues: [Double],
        rollingWindowSeconds: Int = 30
    ) -> Int? {
        guard powerValues.count > rollingWindowSeconds else { return nil }

        // Calculate 30-second rolling averages
        var rollingAverages: [Double] = []
        for i in (rollingWindowSeconds - 1)..<powerValues.count {
            let window = powerValues[(i - rollingWindowSeconds + 1)...i]
            let avg = window.reduce(0, +) / Double(rollingWindowSeconds)
            rollingAverages.append(avg)
        }

        // Calculate 4th power of each rolling average
        let fourthPowers = rollingAverages.map { pow($0, 4) }

        // Average of 4th powers
        let avgFourthPower = fourthPowers.reduce(0, +) / Double(fourthPowers.count)

        // 4th root to get NP
        let normalizedPower = pow(avgFourthPower, 0.25)

        return Int(normalizedPower)
    }

    // MARK: - Normalized Graded Pace (Running)

    /// Calculate Normalized Graded Pace from pace and elevation data
    /// NGP adjusts pace for elevation changes to represent equivalent flat-ground effort
    ///
    /// - Parameters:
    ///   - paceData: Array of (timestamp, pace in sec/km, elevation in meters)
    /// - Returns: NGP in seconds per km
    static func calculateNormalizedGradedPace(
        from paceData: [(timestamp: Date, paceSecPerKm: Double, elevation: Double)]
    ) -> Double? {
        guard paceData.count >= 2 else { return nil }

        var adjustedPaces: [Double] = []

        for i in 1..<paceData.count {
            let current = paceData[i]
            let previous = paceData[i - 1]

            let timeDelta = current.timestamp.timeIntervalSince(previous.timestamp)
            guard timeDelta > 0 else { continue }

            let elevationChange = current.elevation - previous.elevation
            let horizontalDistance = timeDelta / current.paceSecPerKm * 1000 // meters

            guard horizontalDistance > 0 else { continue }

            // Calculate grade as percentage
            let grade = (elevationChange / horizontalDistance) * 100

            // Apply grade adjustment factor
            // This uses the Minetti formula approximation
            let adjustmentFactor = gradeAdjustmentFactor(grade: grade)

            // Adjust pace - uphill is "harder" so we credit it
            let adjustedPace = current.paceSecPerKm / adjustmentFactor
            adjustedPaces.append(adjustedPace)
        }

        guard !adjustedPaces.isEmpty else { return nil }

        // NGP is the average of grade-adjusted paces
        return adjustedPaces.reduce(0, +) / Double(adjustedPaces.count)
    }

    /// Calculate NGP from workout with route data
    static func calculateNormalizedGradedPace(
        pace: Double,          // Average pace sec/km
        duration: TimeInterval,
        totalAscent: Double,   // Total elevation gain in meters
        totalDescent: Double,  // Total elevation loss in meters
        distance: Double       // Distance in meters
    ) -> Double? {
        guard distance > 0, duration > 0 else { return nil }

        // Calculate average grade impact
        let netElevation = totalAscent - totalDescent
        let avgGrade = (netElevation / distance) * 100

        // Also factor in total climbing regardless of net
        let totalClimbing = totalAscent + totalDescent
        let climbingFactor = totalClimbing / distance * 50 // Empirical factor

        // Combined grade effect
        let effectiveGrade = avgGrade + climbingFactor

        let adjustmentFactor = gradeAdjustmentFactor(grade: effectiveGrade)

        return pace / adjustmentFactor
    }

    // MARK: - Grade Adjustment

    /// Returns adjustment factor for a given grade
    /// Based on Minetti et al. research on metabolic cost of running on grades
    /// Factor > 1 means harder (uphill), factor < 1 means easier (downhill)
    static func gradeAdjustmentFactor(grade: Double) -> Double {
        // Coefficients based on metabolic cost research
        // grade is in percentage (-100 to +100)
        let g = grade / 100  // Convert to decimal

        // Polynomial approximation of metabolic cost curve
        // Cost = 155.4g^5 - 30.4g^4 - 43.3g^3 + 46.3g^2 + 19.5g + 3.6
        // We want the relative cost vs flat ground (3.6)

        let cost = 155.4 * pow(g, 5) - 30.4 * pow(g, 4) - 43.3 * pow(g, 3) +
                   46.3 * pow(g, 2) + 19.5 * g + 3.6

        let flatCost = 3.6

        // Return adjustment factor (clamped to reasonable range)
        return max(0.7, min(2.0, cost / flatCost))
    }

    // MARK: - Helper Methods

    /// Resample irregular power data to 1-second intervals
    private static func resampleToOneSecond(_ data: [(timestamp: Date, power: Double)]) -> [Double] {
        guard let first = data.first, let last = data.last else { return [] }

        let totalSeconds = Int(last.timestamp.timeIntervalSince(first.timestamp))
        guard totalSeconds > 0 else { return [] }

        var resampled: [Double] = []
        var dataIndex = 0

        for second in 0..<totalSeconds {
            let targetTime = first.timestamp.addingTimeInterval(Double(second))

            // Find the closest sample
            while dataIndex < data.count - 1 &&
                  data[dataIndex + 1].timestamp <= targetTime {
                dataIndex += 1
            }

            // Linear interpolation if between samples
            if dataIndex < data.count - 1 {
                let before = data[dataIndex]
                let after = data[dataIndex + 1]

                let timeDiff = after.timestamp.timeIntervalSince(before.timestamp)
                let elapsed = targetTime.timeIntervalSince(before.timestamp)

                if timeDiff > 0 {
                    let ratio = elapsed / timeDiff
                    let interpolated = before.power + (after.power - before.power) * ratio
                    resampled.append(interpolated)
                } else {
                    resampled.append(before.power)
                }
            } else {
                resampled.append(data[dataIndex].power)
            }
        }

        return resampled
    }

    // MARK: - Variability Index

    /// Calculate Variability Index (VI = NP / Average Power)
    /// VI > 1.05 indicates variable/surgy effort
    /// VI close to 1.0 indicates steady-state effort
    static func calculateVariabilityIndex(normalizedPower: Int, averagePower: Int) -> Double {
        guard averagePower > 0 else { return 1.0 }
        return Double(normalizedPower) / Double(averagePower)
    }
}
