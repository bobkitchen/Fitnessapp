import Foundation
import SwiftData

/// Service for calibrating PMC values with TrainingPeaks data
@MainActor
final class CalibrationService {

    private let modelContext: ModelContext
    private let ocrService = ScreenshotOCRService()
    private lazy var learningEngine = TSSLearningEngine(modelContext: modelContext)

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Calibration Flow

    /// Process a screenshot and create calibration record
    func processScreenshot(imageData: Data) async throws -> CalibrationRecord {
        // Run OCR
        let ocrResult = try await ocrService.processScreenshot(imageData: imageData)

        guard ocrResult.isValid else {
            throw CalibrationError.noValuesFound
        }

        // Get current calculated values for comparison
        let currentMetrics = try fetchCurrentMetrics()
        let effectiveDate = ocrResult.effectiveDate ?? Date()

        // Create calibration record
        let record = CalibrationRecord(
            effectiveDate: effectiveDate,
            extractedCTL: ocrResult.ctl,
            extractedATL: ocrResult.atl,
            extractedTSB: ocrResult.tsb,
            calculatedCTL: currentMetrics?.ctl ?? 0,
            calculatedATL: currentMetrics?.atl ?? 0,
            calculatedTSB: currentMetrics?.tsb ?? 0,
            ocrConfidence: ocrResult.confidence,
            sourceType: .screenshot
        )

        record.ocrRawText = ocrResult.rawText

        // Save the record
        modelContext.insert(record)
        try modelContext.save()

        // Trigger TSS learning if we have learning data
        if ocrResult.hasLearningData {
            await triggerTSSLearning(
                ocrResult: ocrResult,
                effectiveDate: effectiveDate,
                calibrationRecordId: record.id
            )
        }

        return record
    }

    /// Trigger TSS learning from calibration data
    private func triggerTSSLearning(
        ocrResult: OCRCalibrationResult,
        effectiveDate: Date,
        calibrationRecordId: UUID
    ) async {
        do {
            // Get calculated daily TSS for the effective date
            let calculatedDailyTSS = try fetchCalculatedDailyTSS(for: effectiveDate)

            // Determine the primary activity category for this day
            let (primaryCategory, isMultiSport) = try determinePrimaryActivityCategory(for: effectiveDate)

            // Process the calibration through the learning engine
            try await learningEngine.processCalibration(
                ocrResult: ocrResult,
                calculatedDailyTSS: calculatedDailyTSS,
                primaryActivityCategory: primaryCategory,
                isMultiSport: isMultiSport,
                calibrationRecordId: calibrationRecordId
            )

            print("[CalibrationService] TSS learning triggered successfully")
        } catch {
            print("[CalibrationService] TSS learning failed: \(error)")
            // Don't throw - learning failure shouldn't block calibration
        }
    }

    /// Fetch our calculated daily TSS for a specific date
    private func fetchCalculatedDailyTSS(for date: Date) throws -> Double {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        // Sum TSS from all workouts on this day
        let predicate = #Predicate<WorkoutRecord> { workout in
            workout.startDate >= dayStart && workout.startDate < dayEnd
        }
        let descriptor = FetchDescriptor<WorkoutRecord>(predicate: predicate)
        let workouts = try modelContext.fetch(descriptor)

        return workouts.reduce(0) { $0 + $1.tss }
    }

    /// Determine the primary activity category for a day
    private func determinePrimaryActivityCategory(for date: Date) throws -> (category: ActivityCategory?, isMultiSport: Bool) {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let predicate = #Predicate<WorkoutRecord> { workout in
            workout.startDate >= dayStart && workout.startDate < dayEnd
        }
        let descriptor = FetchDescriptor<WorkoutRecord>(predicate: predicate)
        let workouts = try modelContext.fetch(descriptor)

        guard !workouts.isEmpty else {
            return (nil, false)
        }

        // Check if multiple sport types
        let categories = Set(workouts.map { $0.activityCategory })
        let isMultiSport = categories.count > 1

        // Primary category is the one with most TSS
        var tssByCategory: [ActivityCategory: Double] = [:]
        for workout in workouts {
            tssByCategory[workout.activityCategory, default: 0] += workout.tss
        }

        let primaryCategory = tssByCategory.max(by: { $0.value < $1.value })?.key

        return (primaryCategory, isMultiSport)
    }

    /// Apply calibration to adjust PMC values
    func applyCalibration(_ record: CalibrationRecord) throws {
        guard record.isTrustworthy else {
            throw CalibrationError.lowConfidence
        }

        // Get all metrics from the effective date forward
        let metricsToAdjust = try fetchMetrics(from: record.effectiveDate)

        // Apply the delta to each day's metrics
        for metrics in metricsToAdjust {
            if record.extractedCTL != nil {
                metrics.ctl += record.ctlDelta
            }
            if record.extractedATL != nil {
                metrics.atl += record.atlDelta
            }
            // TSB is always recalculated
            metrics.tsb = metrics.ctl - metrics.atl
        }

        // Mark calibration as applied
        record.calibrationApplied = true
        record.calibrationNote = "Applied delta: CTL \(String(format: "%+.1f", record.ctlDelta)), ATL \(String(format: "%+.1f", record.atlDelta))"

        try modelContext.save()
    }

    /// Create initial seed from user-entered values
    func createInitialSeed(ctl: Double, atl: Double, effectiveDate: Date = Date()) throws {
        let record = CalibrationRecord.createInitialSeed(ctl: ctl, atl: atl, effectiveDate: effectiveDate)

        modelContext.insert(record)

        // Create or update today's metrics with seed values
        if let todayMetrics = try fetchMetricsForDate(effectiveDate) {
            todayMetrics.ctl = ctl
            todayMetrics.atl = atl
            todayMetrics.tsb = ctl - atl
            todayMetrics.source = .trainingPeaksCalibration
        } else {
            let newMetrics = DailyMetrics(
                date: effectiveDate,
                totalTSS: 0,
                ctl: ctl,
                atl: atl,
                tsb: ctl - atl,
                source: .trainingPeaksCalibration
            )
            modelContext.insert(newMetrics)
        }

        try modelContext.save()
    }

    // MARK: - Validation

    /// Check if calibration is needed based on delta thresholds
    func checkCalibrationNeeded(ocrResult: OCRCalibrationResult) throws -> CalibrationCheck {
        let currentMetrics = try fetchCurrentMetrics()

        guard let current = currentMetrics else {
            return CalibrationCheck(
                isNeeded: true,
                reason: "No existing metrics - initial calibration required",
                ctlDelta: nil,
                atlDelta: nil,
                tsbDelta: nil
            )
        }

        var ctlDelta: Double?
        var atlDelta: Double?
        var tsbDelta: Double?

        if let extractedCTL = ocrResult.ctl {
            ctlDelta = extractedCTL - current.ctl
        }

        if let extractedATL = ocrResult.atl {
            atlDelta = extractedATL - current.atl
        }

        if let extractedTSB = ocrResult.tsb {
            tsbDelta = extractedTSB - current.tsb
        }

        let threshold = 5.0
        let needsCalibration = [ctlDelta, atlDelta, tsbDelta].compactMap { $0 }.contains { abs($0) > threshold }

        var reason: String
        if needsCalibration {
            reason = "Values differ significantly from calculated:"
            if let d = ctlDelta, abs(d) > threshold {
                reason += " CTL by \(Int(d))"
            }
            if let d = atlDelta, abs(d) > threshold {
                reason += " ATL by \(Int(d))"
            }
        } else {
            reason = "Values are within acceptable range of calculated metrics"
        }

        return CalibrationCheck(
            isNeeded: needsCalibration,
            reason: reason,
            ctlDelta: ctlDelta,
            atlDelta: atlDelta,
            tsbDelta: tsbDelta
        )
    }

    // MARK: - Data Queries

    private func fetchCurrentMetrics() throws -> DailyMetrics? {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DailyMetrics>(
            predicate: #Predicate { $0.date <= today },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first
    }

    private func fetchMetricsForDate(_ date: Date) throws -> DailyMetrics? {
        let dayStart = Calendar.current.startOfDay(for: date)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        let descriptor = FetchDescriptor<DailyMetrics>(
            predicate: #Predicate { $0.date >= dayStart && $0.date < dayEnd }
        )
        return try modelContext.fetch(descriptor).first
    }

    private func fetchMetrics(from startDate: Date) throws -> [DailyMetrics] {
        let dayStart = Calendar.current.startOfDay(for: startDate)
        let descriptor = FetchDescriptor<DailyMetrics>(
            predicate: #Predicate { $0.date >= dayStart },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    // MARK: - History

    /// Get all calibration records
    func getCalibrationHistory() throws -> [CalibrationRecord] {
        let descriptor = FetchDescriptor<CalibrationRecord>(
            sortBy: [SortDescriptor(\.processedAt, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Delete a calibration record (without undoing its effects)
    func deleteCalibration(_ record: CalibrationRecord) throws {
        modelContext.delete(record)
        try modelContext.save()
    }
}

// MARK: - Supporting Types

struct CalibrationCheck {
    let isNeeded: Bool
    let reason: String
    let ctlDelta: Double?
    let atlDelta: Double?
    let tsbDelta: Double?
}

enum CalibrationError: LocalizedError {
    case noValuesFound
    case lowConfidence
    case saveFailed

    var errorDescription: String? {
        switch self {
        case .noValuesFound:
            return "No PMC values could be extracted from the screenshot"
        case .lowConfidence:
            return "OCR confidence is too low to apply calibration"
        case .saveFailed:
            return "Failed to save calibration data"
        }
    }
}
