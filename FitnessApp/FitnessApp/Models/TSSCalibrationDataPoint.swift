import Foundation
import SwiftData

/// Individual data point for TSS learning
/// Each calibration creates one or more of these to track the relationship
/// between our calculated TSS and TrainingPeaks' values
@Model
final class TSSCalibrationDataPoint {

    // MARK: - Identification

    var id: UUID = UUID()

    /// The date this data point represents
    var effectiveDate: Date

    /// When this data point was created
    var createdAt: Date = Date()

    // MARK: - TSS Values

    /// Daily TSS extracted from TrainingPeaks screenshot
    var extractedDailyTSS: Double?

    /// Our calculated daily TSS for the same day
    var calculatedDailyTSS: Double

    /// Weekly TSS from TrainingPeaks (if visible in screenshot)
    var extractedWeeklyTSS: Double?

    /// Our calculated weekly TSS
    var calculatedWeeklyTSS: Double?

    // MARK: - Derived Values

    /// The scaling ratio: extracted / calculated
    /// e.g., 1.22 means TP is 22% higher than our calculation
    var scalingRatio: Double?

    // MARK: - Activity Context (for per-sport learning)

    /// Primary activity category for this day (if single sport)
    var activityCategoryRaw: String?
    var activityCategory: ActivityCategory? {
        get {
            guard let raw = activityCategoryRaw else { return nil }
            return ActivityCategory(rawValue: raw)
        }
        set { activityCategoryRaw = newValue?.rawValue }
    }

    /// Whether this day had multiple activity types
    var isMultiSport: Bool = false

    /// Intensity bucket for stratified calibration
    var intensityBucketRaw: String?
    var intensityBucket: IntensityBucket? {
        get {
            guard let raw = intensityBucketRaw else { return nil }
            return IntensityBucket(rawValue: raw)
        }
        set { intensityBucketRaw = newValue?.rawValue }
    }

    /// The workout's intensity factor (IF) at time of calibration
    var workoutIntensityFactor: Double?

    // MARK: - Confidence & Validity

    /// OCR confidence from the screenshot extraction
    var ocrConfidence: Double

    /// Whether this data point should be used in learning
    var isValid: Bool = true

    /// Reason if marked invalid
    var invalidReason: String?

    // MARK: - Derivation Method

    /// How the TSS was derived
    var derivationMethodRaw: String = TSSDerivationMethod.direct.rawValue
    var derivationMethod: TSSDerivationMethod {
        get { TSSDerivationMethod(rawValue: derivationMethodRaw) ?? .direct }
        set { derivationMethodRaw = newValue.rawValue }
    }

    /// Reference to the CalibrationRecord this came from
    var calibrationRecordId: UUID?

    // MARK: - Initialization

    init(
        effectiveDate: Date,
        extractedDailyTSS: Double? = nil,
        calculatedDailyTSS: Double,
        ocrConfidence: Double,
        activityCategory: ActivityCategory? = nil,
        derivationMethod: TSSDerivationMethod = .direct,
        calibrationRecordId: UUID? = nil
    ) {
        self.id = UUID()
        self.effectiveDate = effectiveDate
        self.createdAt = Date()
        self.extractedDailyTSS = extractedDailyTSS
        self.calculatedDailyTSS = calculatedDailyTSS
        self.ocrConfidence = ocrConfidence
        self.activityCategoryRaw = activityCategory?.rawValue
        self.derivationMethodRaw = derivationMethod.rawValue
        self.calibrationRecordId = calibrationRecordId

        // Calculate scaling ratio if we have extracted TSS
        if let extracted = extractedDailyTSS, calculatedDailyTSS > 0 {
            self.scalingRatio = extracted / calculatedDailyTSS
        }
    }

    // MARK: - Computed Properties

    /// Whether this data point is usable for learning
    var isUsableForLearning: Bool {
        isValid &&
        scalingRatio != nil &&
        ocrConfidence >= 0.5 &&
        calculatedDailyTSS > 0
    }

    /// How old this data point is in days
    var ageInDays: Int {
        Calendar.current.dateComponents([.day], from: effectiveDate, to: Date()).day ?? 0
    }

    /// Time weight for learning (recent data weighted more)
    /// Uses half-life of 30 days
    var timeWeight: Double {
        let daysSince = Double(ageInDays)
        return pow(0.5, daysSince / 30.0)
    }

    /// Combined weight for learning (time × confidence)
    var learningWeight: Double {
        timeWeight * ocrConfidence
    }

    /// Summary description
    var summary: String {
        var parts: [String] = []

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .short
        parts.append(dateFormatter.string(from: effectiveDate))

        if let extracted = extractedDailyTSS {
            parts.append("TP: \(Int(extracted))")
        }
        parts.append("App: \(Int(calculatedDailyTSS))")

        if let ratio = scalingRatio {
            parts.append("(\(String(format: "%.0f%%", (ratio - 1) * 100)))")
        }

        return parts.joined(separator: " | ")
    }
}

// MARK: - TSS Derivation Method

/// How the TSS value was derived from the screenshot
enum TSSDerivationMethod: String, Codable {
    /// TSS was directly visible and extracted
    case direct = "direct"

    /// TSS was derived from CTL change: TSS = 42 × (CTL_today - CTL_yesterday) + CTL_yesterday
    case derivedFromCTL = "derivedFromCTL"

    /// TSS was derived from ATL change: TSS = 7 × (ATL_today - ATL_yesterday) + ATL_yesterday
    case derivedFromATL = "derivedFromATL"

    /// TSS was derived using both CTL and ATL (cross-validated)
    case derivedCrossValidated = "derivedCrossValidated"

    /// TSS was manually entered by user
    case manual = "manual"

    var description: String {
        switch self {
        case .direct: return "Directly extracted from screenshot"
        case .derivedFromCTL: return "Derived from CTL change (42-day)"
        case .derivedFromATL: return "Derived from ATL change (7-day)"
        case .derivedCrossValidated: return "Derived and cross-validated from CTL+ATL"
        case .manual: return "Manually entered"
        }
    }
}

// MARK: - Factory Methods

extension TSSCalibrationDataPoint {

    /// Create data point when TSS is directly available
    static func fromDirectTSS(
        effectiveDate: Date,
        extractedTSS: Double,
        calculatedTSS: Double,
        ocrConfidence: Double,
        activityCategory: ActivityCategory? = nil,
        calibrationRecordId: UUID? = nil
    ) -> TSSCalibrationDataPoint {
        TSSCalibrationDataPoint(
            effectiveDate: effectiveDate,
            extractedDailyTSS: extractedTSS,
            calculatedDailyTSS: calculatedTSS,
            ocrConfidence: ocrConfidence,
            activityCategory: activityCategory,
            derivationMethod: .direct,
            calibrationRecordId: calibrationRecordId
        )
    }

    /// Derive TSS from CTL change using the formula:
    /// TSS_today = 42 × (CTL_today - CTL_yesterday) + CTL_yesterday
    static func deriveFromCTL(
        effectiveDate: Date,
        todayCTL: Double,
        yesterdayCTL: Double,
        calculatedTSS: Double,
        ocrConfidence: Double,
        activityCategory: ActivityCategory? = nil,
        calibrationRecordId: UUID? = nil
    ) -> TSSCalibrationDataPoint {
        let derivedTSS = 42.0 * (todayCTL - yesterdayCTL) + yesterdayCTL

        let dataPoint = TSSCalibrationDataPoint(
            effectiveDate: effectiveDate,
            extractedDailyTSS: max(0, derivedTSS), // TSS can't be negative
            calculatedDailyTSS: calculatedTSS,
            ocrConfidence: ocrConfidence * 0.9, // Slightly lower confidence for derived values
            activityCategory: activityCategory,
            derivationMethod: .derivedFromCTL,
            calibrationRecordId: calibrationRecordId
        )
        return dataPoint
    }

    /// Derive TSS from ATL change using the formula:
    /// TSS_today = 7 × (ATL_today - ATL_yesterday) + ATL_yesterday
    static func deriveFromATL(
        effectiveDate: Date,
        todayATL: Double,
        yesterdayATL: Double,
        calculatedTSS: Double,
        ocrConfidence: Double,
        activityCategory: ActivityCategory? = nil,
        calibrationRecordId: UUID? = nil
    ) -> TSSCalibrationDataPoint {
        let derivedTSS = 7.0 * (todayATL - yesterdayATL) + yesterdayATL

        let dataPoint = TSSCalibrationDataPoint(
            effectiveDate: effectiveDate,
            extractedDailyTSS: max(0, derivedTSS),
            calculatedDailyTSS: calculatedTSS,
            ocrConfidence: ocrConfidence * 0.9,
            activityCategory: activityCategory,
            derivationMethod: .derivedFromATL,
            calibrationRecordId: calibrationRecordId
        )
        return dataPoint
    }

    /// Derive TSS using both CTL and ATL, cross-validating for higher confidence
    static func deriveWithCrossValidation(
        effectiveDate: Date,
        todayCTL: Double,
        yesterdayCTL: Double,
        todayATL: Double,
        yesterdayATL: Double,
        calculatedTSS: Double,
        ocrConfidence: Double,
        activityCategory: ActivityCategory? = nil,
        calibrationRecordId: UUID? = nil
    ) -> TSSCalibrationDataPoint? {
        let tssFromCTL = 42.0 * (todayCTL - yesterdayCTL) + yesterdayCTL
        let tssFromATL = 7.0 * (todayATL - yesterdayATL) + yesterdayATL

        // Both estimates should be non-negative
        guard tssFromCTL >= 0 && tssFromATL >= 0 else { return nil }

        // Check if estimates agree within 20%
        let avgTSS = (tssFromCTL + tssFromATL) / 2
        let difference = abs(tssFromCTL - tssFromATL)
        let agreement = avgTSS > 0 ? (1 - difference / avgTSS) : 0

        // Only use cross-validated if estimates reasonably agree
        guard agreement >= 0.8 else { return nil }

        let dataPoint = TSSCalibrationDataPoint(
            effectiveDate: effectiveDate,
            extractedDailyTSS: avgTSS,
            calculatedDailyTSS: calculatedTSS,
            ocrConfidence: ocrConfidence * min(1.0, agreement), // Higher confidence when estimates agree
            activityCategory: activityCategory,
            derivationMethod: .derivedCrossValidated,
            calibrationRecordId: calibrationRecordId
        )
        return dataPoint
    }
}
