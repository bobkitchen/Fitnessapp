import Foundation
import SwiftData

/// Records calibration data from TrainingPeaks screenshots for PMC alignment
@Model
final class CalibrationRecord {
    var id: UUID
    var capturedAt: Date                    // When the screenshot was taken
    var processedAt: Date                   // When we processed it
    var effectiveDate: Date                 // The date the PMC values represent

    // MARK: - Extracted Values (from OCR)
    var extractedCTL: Double?               // CTL from TrainingPeaks screenshot
    var extractedATL: Double?               // ATL from TrainingPeaks screenshot
    var extractedTSB: Double?               // TSB from TrainingPeaks screenshot

    // MARK: - Calculated Values (our engine)
    var calculatedCTL: Double               // Our CTL at same date
    var calculatedATL: Double               // Our ATL at same date
    var calculatedTSB: Double               // Our TSB at same date

    // MARK: - Deltas
    var ctlDelta: Double                    // extractedCTL - calculatedCTL
    var atlDelta: Double                    // extractedATL - calculatedATL
    var tsbDelta: Double                    // extractedTSB - calculatedTSB

    // MARK: - Calibration Decision
    var calibrationApplied: Bool            // Whether we applied correction
    var calibrationNote: String?            // Why/what we calibrated

    // MARK: - OCR Metadata
    var ocrConfidence: Double               // 0-1 confidence score
    var ocrRawText: String?                 // Full extracted text
    var screenshotPath: String?             // Path to stored screenshot

    // MARK: - Source
    var sourceTypeRaw: String
    var sourceType: CalibrationSource {
        get { CalibrationSource(rawValue: sourceTypeRaw) ?? .screenshot }
        set { sourceTypeRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        effectiveDate: Date,
        extractedCTL: Double? = nil,
        extractedATL: Double? = nil,
        extractedTSB: Double? = nil,
        calculatedCTL: Double,
        calculatedATL: Double,
        calculatedTSB: Double,
        ocrConfidence: Double = 0,
        sourceType: CalibrationSource = .screenshot
    ) {
        self.id = id
        self.capturedAt = Date()
        self.processedAt = Date()
        self.effectiveDate = effectiveDate

        self.extractedCTL = extractedCTL
        self.extractedATL = extractedATL
        self.extractedTSB = extractedTSB

        self.calculatedCTL = calculatedCTL
        self.calculatedATL = calculatedATL
        self.calculatedTSB = calculatedTSB

        // Calculate deltas
        self.ctlDelta = (extractedCTL ?? calculatedCTL) - calculatedCTL
        self.atlDelta = (extractedATL ?? calculatedATL) - calculatedATL
        self.tsbDelta = (extractedTSB ?? calculatedTSB) - calculatedTSB

        self.calibrationApplied = false
        self.ocrConfidence = ocrConfidence
        self.sourceTypeRaw = sourceType.rawValue
    }

    // MARK: - Computed Properties

    /// Whether calibration is needed (delta > threshold)
    var needsCalibration: Bool {
        let threshold = 5.0
        return abs(ctlDelta) > threshold ||
               abs(atlDelta) > threshold ||
               abs(tsbDelta) > threshold
    }

    /// Summary of deltas
    var deltaSummary: String {
        var parts: [String] = []
        if let _ = extractedCTL {
            parts.append("CTL: \(ctlDelta >= 0 ? "+" : "")\(String(format: "%.1f", ctlDelta))")
        }
        if let _ = extractedATL {
            parts.append("ATL: \(atlDelta >= 0 ? "+" : "")\(String(format: "%.1f", atlDelta))")
        }
        if let _ = extractedTSB {
            parts.append("TSB: \(tsbDelta >= 0 ? "+" : "")\(String(format: "%.1f", tsbDelta))")
        }
        return parts.joined(separator: ", ")
    }

    /// Confidence level description
    var confidenceLevel: String {
        switch ocrConfidence {
        case 0.9...: return "High"
        case 0.7..<0.9: return "Medium"
        case 0.5..<0.7: return "Low"
        default: return "Very Low"
        }
    }

    /// Whether the OCR result should be trusted
    var isTrustworthy: Bool {
        ocrConfidence >= 0.7 && (extractedCTL != nil || extractedATL != nil || extractedTSB != nil)
    }
}

// MARK: - Calibration Source

nonisolated enum CalibrationSource: String, Codable, Sendable {
    case screenshot = "Screenshot"          // TrainingPeaks screenshot OCR
    case manual = "Manual"                  // User-entered values
    case api = "API"                        // Future: direct API sync
    case initialSeed = "Initial Seed"       // First-time setup values
}

// MARK: - Calibration Manager Helper

extension CalibrationRecord {
    /// Apply calibration to a daily metrics record
    func applyTo(_ metrics: DailyMetrics) {
        if extractedCTL != nil {
            metrics.ctl += ctlDelta
        }
        if extractedATL != nil {
            metrics.atl += atlDelta
        }
        // TSB is derived, will be recalculated
        metrics.tsb = metrics.ctl - metrics.atl
    }

    /// Create initial seed calibration record
    static func createInitialSeed(
        ctl: Double,
        atl: Double,
        effectiveDate: Date = Date()
    ) -> CalibrationRecord {
        let record = CalibrationRecord(
            effectiveDate: effectiveDate,
            extractedCTL: ctl,
            extractedATL: atl,
            extractedTSB: ctl - atl,
            calculatedCTL: 0,
            calculatedATL: 0,
            calculatedTSB: 0,
            ocrConfidence: 1.0,
            sourceType: .initialSeed
        )
        record.calibrationApplied = true
        record.calibrationNote = "Initial PMC seed values from user"
        return record
    }
}

// MARK: - OCR Result

/// Intermediate result from screenshot OCR
nonisolated struct OCRCalibrationResult: Sendable {
    let effectiveDate: Date?
    let ctl: Double?
    let atl: Double?
    let tsb: Double?
    let confidence: Double
    let rawText: String

    // MARK: - TSS Learning Fields

    /// Today's TSS directly extracted from screenshot (if visible)
    let dailyTSS: Double?

    /// Weekly TSS total if visible in screenshot
    let weeklyTSS: Double?

    /// Debug log showing how values were detected and matched
    let debugLog: String?

    // MARK: - Validation

    var isValid: Bool {
        confidence >= 0.5 && (ctl != nil || atl != nil || tsb != nil)
    }

    /// Whether this result can be used for TSS learning
    var hasLearningData: Bool {
        dailyTSS != nil || (ctl != nil && atl != nil)
    }

    var extractedValuesDescription: String {
        var parts: [String] = []
        if let ctl { parts.append("CTL: \(Int(ctl))") }
        if let atl { parts.append("ATL: \(Int(atl))") }
        if let tsb { parts.append("TSB: \(Int(tsb))") }
        if let tss = dailyTSS { parts.append("TSS: \(Int(tss))") }
        return parts.isEmpty ? "No values found" : parts.joined(separator: ", ")
    }

    // MARK: - Initialization

    init(
        effectiveDate: Date?,
        ctl: Double?,
        atl: Double?,
        tsb: Double?,
        confidence: Double,
        rawText: String,
        dailyTSS: Double? = nil,
        weeklyTSS: Double? = nil,
        debugLog: String? = nil
    ) {
        self.effectiveDate = effectiveDate
        self.ctl = ctl
        self.atl = atl
        self.tsb = tsb
        self.confidence = confidence
        self.rawText = rawText
        self.dailyTSS = dailyTSS
        self.weeklyTSS = weeklyTSS
        self.debugLog = debugLog
    }
}
