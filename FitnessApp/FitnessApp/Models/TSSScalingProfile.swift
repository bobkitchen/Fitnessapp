import Foundation
import SwiftData

/// Stores learned TSS scaling factors based on calibration data
/// This is a singleton model - only one instance should exist
@Model
final class TSSScalingProfile {

    // MARK: - Global Scaling

    /// Overall TSS scaling factor (e.g., 1.22 = TrainingPeaks is 22% higher)
    var globalScalingFactor: Double = 1.0

    /// Confidence in the global scaling factor (0-1)
    var globalConfidence: Double = 0.0

    /// Number of calibration samples used for global scaling
    var globalSampleCount: Int = 0

    // MARK: - Per-Sport Scaling (Optional, for more accuracy)

    /// Cycling-specific scaling factor
    var cyclingScalingFactor: Double?
    var cyclingSampleCount: Int = 0

    /// Running-specific scaling factor
    var runningScalingFactor: Double?
    var runningSampleCount: Int = 0

    /// Swimming-specific scaling factor
    var swimScalingFactor: Double?
    var swimSampleCount: Int = 0

    // MARK: - Configuration

    /// Whether TSS learning is enabled
    var learningEnabled: Bool = true

    /// Minimum samples required before applying scaling with confidence
    var minSamplesForConfidence: Int = 3

    /// Sanity bounds for scaling factor
    var minScalingFactor: Double = 0.8
    var maxScalingFactor: Double = 1.5

    // MARK: - URL Import Calibration Controls

    /// Whether the user has marked TSS calibration as complete
    var tssCalibrationComplete: Bool = false

    /// Confidence threshold to auto-suggest disabling URL import (0.95 = 95%)
    var autoDisableThreshold: Double = 0.95

    /// Whether URL import feature is enabled (user can disable after calibration)
    var urlImportEnabled: Bool = true

    // MARK: - Metadata

    /// When this profile was created
    var createdAt: Date = Date()

    /// When scaling factors were last updated
    var lastUpdatedAt: Date = Date()

    // MARK: - Initialization

    init() {
        self.createdAt = Date()
        self.lastUpdatedAt = Date()
    }

    // MARK: - Computed Properties

    /// Whether we have enough confidence to apply scaling
    var canApplyScaling: Bool {
        learningEnabled &&
        globalSampleCount >= minSamplesForConfidence &&
        globalConfidence >= 0.5 &&
        globalScalingFactor >= minScalingFactor &&
        globalScalingFactor <= maxScalingFactor
    }

    /// Get the scaling factor for a specific activity category
    func scalingFactor(for category: ActivityCategory) -> Double {
        guard canApplyScaling else { return 1.0 }

        // Use sport-specific factor if available with sufficient samples
        switch category {
        case .bike:
            if let factor = cyclingScalingFactor, cyclingSampleCount >= minSamplesForConfidence {
                return factor
            }
        case .run:
            if let factor = runningScalingFactor, runningSampleCount >= minSamplesForConfidence {
                return factor
            }
        case .swim:
            if let factor = swimScalingFactor, swimSampleCount >= minSamplesForConfidence {
                return factor
            }
        default:
            break
        }

        // Fall back to global factor
        return globalScalingFactor
    }

    /// Human-readable confidence level
    var confidenceLevel: String {
        switch globalConfidence {
        case 0.9...: return "Very High"
        case 0.7..<0.9: return "High"
        case 0.5..<0.7: return "Medium"
        case 0.3..<0.5: return "Low"
        default: return "Insufficient Data"
        }
    }

    /// Status summary for UI display
    var statusSummary: String {
        if globalSampleCount == 0 {
            return "No calibration data yet"
        } else if globalSampleCount < minSamplesForConfidence {
            return "Need \(minSamplesForConfidence - globalSampleCount) more calibrations"
        } else if !canApplyScaling {
            return "Scaling factor outside safe bounds"
        } else {
            return "Active - applying \(String(format: "%.0f%%", (globalScalingFactor - 1) * 100)) adjustment"
        }
    }

    /// Per-sport status for UI display
    var perSportStatus: [(category: ActivityCategory, factor: Double?, samples: Int, status: String)] {
        [
            (
                .bike,
                cyclingScalingFactor,
                cyclingSampleCount,
                cyclingSampleCount >= minSamplesForConfidence ? "Active" : "Need more data"
            ),
            (
                .run,
                runningScalingFactor,
                runningSampleCount,
                runningSampleCount >= minSamplesForConfidence ? "Active" : "Need more data"
            ),
            (
                .swim,
                swimScalingFactor,
                swimSampleCount,
                swimSampleCount >= minSamplesForConfidence ? "Active" : "Need more data"
            )
        ]
    }

    // MARK: - URL Import Calibration Status

    /// Whether calibration confidence has reached auto-disable threshold
    var shouldSuggestDisablingImport: Bool {
        globalConfidence >= autoDisableThreshold && globalSampleCount >= 10
    }

    /// Whether URL import should be shown in settings
    var showURLImportOption: Bool {
        urlImportEnabled && !tssCalibrationComplete
    }

    /// Calibration progress for URL imports (0-1)
    var calibrationProgress: Double {
        // Weight both sample count and confidence
        let sampleProgress = min(1.0, Double(globalSampleCount) / 10.0)
        let confidenceProgress = min(1.0, globalConfidence / autoDisableThreshold)
        return (sampleProgress + confidenceProgress) / 2.0
    }

    /// Human-readable calibration status for URL imports
    var urlImportCalibrationStatus: String {
        if tssCalibrationComplete {
            return "Calibration complete"
        } else if globalSampleCount == 0 {
            return "Not started"
        } else if shouldSuggestDisablingImport {
            return "Ready to complete"
        } else {
            return "In progress (\(String(format: "%.0f%%", calibrationProgress * 100)))"
        }
    }
}
