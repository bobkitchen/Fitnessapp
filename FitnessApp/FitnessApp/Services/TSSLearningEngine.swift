import Foundation
import SwiftData

/// Engine that learns TSS scaling factors from calibration data
/// Uses time-weighted averaging to continuously improve TSS accuracy
@MainActor
final class TSSLearningEngine {

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Learning Algorithm

    /// Process a new calibration and update scaling factors
    func processCalibration(
        ocrResult: OCRCalibrationResult,
        calculatedDailyTSS: Double,
        primaryActivityCategory: ActivityCategory?,
        isMultiSport: Bool,
        calibrationRecordId: UUID?
    ) async throws {
        // Get or create the scaling profile
        let profile = try getOrCreateScalingProfile()

        guard profile.learningEnabled else {
            print("[TSSLearning] Learning disabled, skipping")
            return
        }

        // Create data point(s) from the calibration
        let dataPoints = createDataPoints(
            from: ocrResult,
            calculatedDailyTSS: calculatedDailyTSS,
            primaryActivityCategory: primaryActivityCategory,
            isMultiSport: isMultiSport,
            calibrationRecordId: calibrationRecordId
        )

        // Save data points
        for dataPoint in dataPoints {
            modelContext.insert(dataPoint)
        }

        // Recalculate scaling factors
        try recalculateScalingFactors(profile: profile)

        try modelContext.save()

        print("[TSSLearning] Processed calibration: \(dataPoints.count) data points created")
        print("[TSSLearning] Updated scaling factor: \(String(format: "%.3f", profile.globalScalingFactor)) (confidence: \(String(format: "%.0f%%", profile.globalConfidence * 100)))")
    }

    // MARK: - Data Point Creation

    /// Create calibration data points from OCR result
    private func createDataPoints(
        from ocrResult: OCRCalibrationResult,
        calculatedDailyTSS: Double,
        primaryActivityCategory: ActivityCategory?,
        isMultiSport: Bool,
        calibrationRecordId: UUID?
    ) -> [TSSCalibrationDataPoint] {
        var dataPoints: [TSSCalibrationDataPoint] = []
        let effectiveDate = ocrResult.effectiveDate ?? Date()

        // Priority 1: Direct TSS extraction
        if let extractedTSS = ocrResult.dailyTSS, extractedTSS > 0 {
            let dataPoint = TSSCalibrationDataPoint.fromDirectTSS(
                effectiveDate: effectiveDate,
                extractedTSS: extractedTSS,
                calculatedTSS: calculatedDailyTSS,
                ocrConfidence: ocrResult.confidence,
                activityCategory: isMultiSport ? nil : primaryActivityCategory,
                calibrationRecordId: calibrationRecordId
            )
            dataPoint.isMultiSport = isMultiSport
            dataPoints.append(dataPoint)

            print("[TSSLearning] Created direct TSS data point: extracted=\(Int(extractedTSS)), calculated=\(Int(calculatedDailyTSS))")
            return dataPoints
        }

        // Priority 2: Derive from CTL/ATL changes
        // This requires yesterday's values, which we need to look up
        if let todayCTL = ocrResult.ctl, let todayATL = ocrResult.atl {
            if let yesterdayValues = try? fetchYesterdayValues(before: effectiveDate) {
                // Try cross-validated derivation first (most accurate)
                if let crossValidated = TSSCalibrationDataPoint.deriveWithCrossValidation(
                    effectiveDate: effectiveDate,
                    todayCTL: todayCTL,
                    yesterdayCTL: yesterdayValues.ctl,
                    todayATL: todayATL,
                    yesterdayATL: yesterdayValues.atl,
                    calculatedTSS: calculatedDailyTSS,
                    ocrConfidence: ocrResult.confidence,
                    activityCategory: isMultiSport ? nil : primaryActivityCategory,
                    calibrationRecordId: calibrationRecordId
                ) {
                    crossValidated.isMultiSport = isMultiSport
                    dataPoints.append(crossValidated)

                    if let extracted = crossValidated.extractedDailyTSS {
                        print("[TSSLearning] Created cross-validated TSS data point: derived=\(Int(extracted)), calculated=\(Int(calculatedDailyTSS))")
                    }
                    return dataPoints
                }

                // Fall back to CTL-derived
                let ctlDerived = TSSCalibrationDataPoint.deriveFromCTL(
                    effectiveDate: effectiveDate,
                    todayCTL: todayCTL,
                    yesterdayCTL: yesterdayValues.ctl,
                    calculatedTSS: calculatedDailyTSS,
                    ocrConfidence: ocrResult.confidence,
                    activityCategory: isMultiSport ? nil : primaryActivityCategory,
                    calibrationRecordId: calibrationRecordId
                )
                ctlDerived.isMultiSport = isMultiSport
                dataPoints.append(ctlDerived)

                if let extracted = ctlDerived.extractedDailyTSS {
                    print("[TSSLearning] Created CTL-derived TSS data point: derived=\(Int(extracted)), calculated=\(Int(calculatedDailyTSS))")
                }
            }
        }

        return dataPoints
    }

    // MARK: - Scaling Factor Calculation

    /// Recalculate all scaling factors from historical data
    func recalculateScalingFactors(profile: TSSScalingProfile) throws {
        let dataPoints = try fetchValidDataPoints()

        guard !dataPoints.isEmpty else {
            print("[TSSLearning] No valid data points for recalculation")
            return
        }

        // Calculate global scaling factor
        let (globalFactor, globalConfidence, globalCount) = calculateWeightedScalingFactor(from: dataPoints)

        profile.globalScalingFactor = globalFactor
        profile.globalConfidence = globalConfidence
        profile.globalSampleCount = globalCount
        profile.lastUpdatedAt = Date()

        // Calculate per-sport scaling factors
        calculatePerSportFactors(profile: profile, dataPoints: dataPoints)
    }

    /// Calculate time-weighted scaling factor
    /// Formula: scalingFactor = Σ(ratio × weight) / Σ(weight)
    /// where weight = timeWeight × ocrConfidence
    private func calculateWeightedScalingFactor(
        from dataPoints: [TSSCalibrationDataPoint]
    ) -> (factor: Double, confidence: Double, count: Int) {
        let validPoints = dataPoints.filter { $0.isUsableForLearning }

        guard !validPoints.isEmpty else {
            return (1.0, 0.0, 0)
        }

        var weightedSum = 0.0
        var totalWeight = 0.0
        var ratios: [Double] = []

        for point in validPoints {
            guard let ratio = point.scalingRatio else { continue }
            let weight = point.learningWeight

            weightedSum += ratio * weight
            totalWeight += weight
            ratios.append(ratio)
        }

        let factor = totalWeight > 0 ? weightedSum / totalWeight : 1.0

        // Calculate confidence
        let confidence = calculateConfidence(
            sampleCount: validPoints.count,
            ratios: ratios,
            dataPoints: validPoints
        )

        return (factor, confidence, validPoints.count)
    }

    /// Calculate confidence score based on sample count, variance, and recency
    /// confidence = (sampleScore × 0.4) + (varianceScore × 0.4) + (recencyScore × 0.2)
    private func calculateConfidence(
        sampleCount: Int,
        ratios: [Double],
        dataPoints: [TSSCalibrationDataPoint]
    ) -> Double {
        // Sample score: min(1.0, count / 10)
        let sampleScore = min(1.0, Double(sampleCount) / 10.0)

        // Variance score: max(0, 1.0 - sqrt(variance) / 0.3)
        let variance = calculateVariance(ratios)
        let varianceScore = max(0, 1.0 - sqrt(variance) / 0.3)

        // Recency score: average time weight
        let avgTimeWeight = dataPoints.reduce(0.0) { $0 + $1.timeWeight } / Double(max(1, dataPoints.count))
        let recencyScore = avgTimeWeight

        return (sampleScore * 0.4) + (varianceScore * 0.4) + (recencyScore * 0.2)
    }

    /// Calculate variance of an array of doubles
    private func calculateVariance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }

        let mean = values.reduce(0.0, +) / Double(values.count)
        let squaredDifferences = values.map { pow($0 - mean, 2) }
        return squaredDifferences.reduce(0.0, +) / Double(values.count - 1)
    }

    /// Calculate per-sport scaling factors
    private func calculatePerSportFactors(
        profile: TSSScalingProfile,
        dataPoints: [TSSCalibrationDataPoint]
    ) {
        // Cycling
        let cyclingPoints = dataPoints.filter { $0.activityCategory == .bike && !$0.isMultiSport }
        if !cyclingPoints.isEmpty {
            let (factor, _, count) = calculateWeightedScalingFactor(from: cyclingPoints)
            profile.cyclingScalingFactor = factor
            profile.cyclingSampleCount = count
        }

        // Running
        let runningPoints = dataPoints.filter { $0.activityCategory == .run && !$0.isMultiSport }
        if !runningPoints.isEmpty {
            let (factor, _, count) = calculateWeightedScalingFactor(from: runningPoints)
            profile.runningScalingFactor = factor
            profile.runningSampleCount = count
        }

        // Swimming
        let swimmingPoints = dataPoints.filter { $0.activityCategory == .swim && !$0.isMultiSport }
        if !swimmingPoints.isEmpty {
            let (factor, _, count) = calculateWeightedScalingFactor(from: swimmingPoints)
            profile.swimScalingFactor = factor
            profile.swimSampleCount = count
        }

        // Calculate intensity-stratified factors
        calculatePerIntensityFactors(profile: profile, dataPoints: dataPoints)
    }

    /// Calculate per-intensity scaling factors (stratified by IF)
    private func calculatePerIntensityFactors(
        profile: TSSScalingProfile,
        dataPoints: [TSSCalibrationDataPoint]
    ) {
        // Recovery (IF < 0.75)
        let recoveryPoints = dataPoints.filter { $0.intensityBucket == .recovery }
        if !recoveryPoints.isEmpty {
            let (factor, _, count) = calculateWeightedScalingFactor(from: recoveryPoints)
            profile.recoveryScalingFactor = factor
            profile.recoverySampleCount = count
        }

        // Endurance (IF 0.75-0.90)
        let endurancePoints = dataPoints.filter { $0.intensityBucket == .endurance }
        if !endurancePoints.isEmpty {
            let (factor, _, count) = calculateWeightedScalingFactor(from: endurancePoints)
            profile.enduranceScalingFactor = factor
            profile.enduranceSampleCount = count
        }

        // Tempo (IF 0.90-1.05)
        let tempoPoints = dataPoints.filter { $0.intensityBucket == .tempo }
        if !tempoPoints.isEmpty {
            let (factor, _, count) = calculateWeightedScalingFactor(from: tempoPoints)
            profile.tempoScalingFactor = factor
            profile.tempoSampleCount = count
        }

        // High Intensity (IF > 1.05)
        let highIntensityPoints = dataPoints.filter { $0.intensityBucket == .highIntensity }
        if !highIntensityPoints.isEmpty {
            let (factor, _, count) = calculateWeightedScalingFactor(from: highIntensityPoints)
            profile.highIntensityScalingFactor = factor
            profile.highIntensitySampleCount = count
        }

        print("[TSSLearning] Intensity factors: recovery=\(profile.recoveryScalingFactor.map { String(format: "%.3f", $0) } ?? "nil")(\(profile.recoverySampleCount)), endurance=\(profile.enduranceScalingFactor.map { String(format: "%.3f", $0) } ?? "nil")(\(profile.enduranceSampleCount)), tempo=\(profile.tempoScalingFactor.map { String(format: "%.3f", $0) } ?? "nil")(\(profile.tempoSampleCount)), high=\(profile.highIntensityScalingFactor.map { String(format: "%.3f", $0) } ?? "nil")(\(profile.highIntensitySampleCount))")
    }

    // MARK: - Data Queries

    /// Get or create the singleton scaling profile
    func getOrCreateScalingProfile() throws -> TSSScalingProfile {
        let descriptor = FetchDescriptor<TSSScalingProfile>()
        let existing = try modelContext.fetch(descriptor)

        if let profile = existing.first {
            return profile
        }

        let newProfile = TSSScalingProfile()
        modelContext.insert(newProfile)
        return newProfile
    }

    /// Fetch the current scaling profile (nil if none exists)
    func fetchScalingProfile() throws -> TSSScalingProfile? {
        let descriptor = FetchDescriptor<TSSScalingProfile>()
        return try modelContext.fetch(descriptor).first
    }

    /// Fetch all valid calibration data points
    private func fetchValidDataPoints() throws -> [TSSCalibrationDataPoint] {
        let descriptor = FetchDescriptor<TSSCalibrationDataPoint>(
            predicate: #Predicate { $0.isValid },
            sortBy: [SortDescriptor(\.effectiveDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    /// Fetch yesterday's CTL/ATL values for TSS derivation
    private func fetchYesterdayValues(before date: Date) throws -> (ctl: Double, atl: Double)? {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: date)) else {
            return nil
        }
        let dayAfterYesterday = calendar.date(byAdding: .day, value: 1, to: yesterday)!

        // First try to find a calibration record from yesterday
        let calDescriptor = FetchDescriptor<CalibrationRecord>(
            predicate: #Predicate { record in
                record.effectiveDate >= yesterday && record.effectiveDate < dayAfterYesterday
            },
            sortBy: [SortDescriptor(\.effectiveDate, order: .reverse)]
        )

        if let calibration = try modelContext.fetch(calDescriptor).first,
           let ctl = calibration.extractedCTL,
           let atl = calibration.extractedATL {
            return (ctl, atl)
        }

        // Fall back to DailyMetrics
        let metricsDescriptor = FetchDescriptor<DailyMetrics>(
            predicate: #Predicate { metrics in
                metrics.date >= yesterday && metrics.date < dayAfterYesterday
            }
        )

        if let metrics = try modelContext.fetch(metricsDescriptor).first {
            return (metrics.ctl, metrics.atl)
        }

        return nil
    }

    // MARK: - Direct Workout Calibration

    /// Record a direct TSS comparison from a TrainingPeaks workout URL import
    /// This provides high-confidence calibration data for the learning algorithm
    func recordDirectTSSComparison(
        workout: WorkoutRecord,
        trainingPeaksTSS: Double,
        trainingPeaksIF: Double?,
        matchConfidence: Double
    ) async throws {
        let profile = try getOrCreateScalingProfile()

        guard profile.learningEnabled else {
            print("[TSSLearning] Learning disabled, skipping direct comparison")
            return
        }

        // Create a high-confidence calibration data point
        let dataPoint = TSSCalibrationDataPoint(
            effectiveDate: workout.startDate,
            extractedDailyTSS: trainingPeaksTSS,
            calculatedDailyTSS: workout.tss,
            ocrConfidence: matchConfidence,  // Use match confidence as quality indicator
            activityCategory: workout.activityCategory,
            derivationMethod: .direct,
            calibrationRecordId: nil  // No OCR calibration record
        )

        // Mark as from URL import (not multi-sport since it's a single workout)
        dataPoint.isMultiSport = false

        // Capture intensity data for stratified calibration
        let workoutIF = trainingPeaksIF ?? workout.intensityFactor
        if workoutIF > 0 {
            dataPoint.workoutIntensityFactor = workoutIF
            dataPoint.intensityBucket = IntensityBucket(intensityFactor: workoutIF)
        }

        modelContext.insert(dataPoint)

        // Recalculate scaling factors with new data
        try recalculateScalingFactors(profile: profile)

        try modelContext.save()

        let ratio = trainingPeaksTSS / max(1, workout.tss)
        print("[TSSLearning] Recorded direct TSS comparison:")
        print("  - Workout: \(workout.activityCategory.rawValue) on \(workout.dateFormatted)")
        print("  - TP TSS: \(Int(trainingPeaksTSS)), App TSS: \(Int(workout.tss))")
        print("  - Ratio: \(String(format: "%.2f", ratio)) (\(String(format: "%.0f%%", (ratio - 1) * 100)) difference)")
        print("  - New scaling factor: \(String(format: "%.3f", profile.globalScalingFactor))")
        print("  - Confidence: \(String(format: "%.0f%%", profile.globalConfidence * 100))")
    }

    /// Record combined TSS and PMC calibration from a TrainingPeaks workout import
    /// This is the preferred method when users provide both workout TSS and current PMC values
    func recordCombinedCalibration(
        workout: WorkoutRecord,
        trainingPeaksTSS: Double,
        trainingPeaksIF: Double?,
        pmcValues: (ctl: Double, atl: Double, tsb: Double),
        matchConfidence: Double
    ) async throws {
        let profile = try getOrCreateScalingProfile()

        guard profile.learningEnabled else {
            print("[TSSLearning] Learning disabled, skipping combined calibration")
            return
        }

        // 1. Record TSS comparison (same as recordDirectTSSComparison)
        let tssDataPoint = TSSCalibrationDataPoint(
            effectiveDate: workout.startDate,
            extractedDailyTSS: trainingPeaksTSS,
            calculatedDailyTSS: workout.tss,
            ocrConfidence: matchConfidence,
            activityCategory: workout.activityCategory,
            derivationMethod: .direct,
            calibrationRecordId: nil
        )
        tssDataPoint.isMultiSport = false

        // Capture intensity data for stratified calibration
        let workoutIF = trainingPeaksIF ?? workout.intensityFactor
        if workoutIF > 0 {
            tssDataPoint.workoutIntensityFactor = workoutIF
            tssDataPoint.intensityBucket = IntensityBucket(intensityFactor: workoutIF)
        }

        modelContext.insert(tssDataPoint)

        // 2. Record PMC calibration
        try recordPMCCalibration(
            extractedCTL: pmcValues.ctl,
            extractedATL: pmcValues.atl,
            extractedTSB: pmcValues.tsb,
            effectiveDate: workout.startDate
        )

        // 3. Recalculate scaling factors with new data
        try recalculateScalingFactors(profile: profile)

        try modelContext.save()

        let tssRatio = trainingPeaksTSS / max(1, workout.tss)
        print("[TSSLearning] Recorded combined calibration:")
        print("  - Workout: \(workout.activityCategory.rawValue) on \(workout.dateFormatted)")
        print("  - TP TSS: \(Int(trainingPeaksTSS)), App TSS: \(Int(workout.tss)), Ratio: \(String(format: "%.2f", tssRatio))")
        print("  - PMC: CTL=\(Int(pmcValues.ctl)), ATL=\(Int(pmcValues.atl)), TSB=\(Int(pmcValues.tsb))")
        print("  - New scaling factor: \(String(format: "%.3f", profile.globalScalingFactor))")
    }

    /// Record PMC calibration from user-provided values
    /// Updates the CalibrationRecord with PMC values for historical reference
    private func recordPMCCalibration(
        extractedCTL: Double,
        extractedATL: Double,
        extractedTSB: Double,
        effectiveDate: Date
    ) throws {
        // Find or create DailyMetrics for the effective date
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: effectiveDate)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        let descriptor = FetchDescriptor<DailyMetrics>(
            predicate: #Predicate { metrics in
                metrics.date >= startOfDay && metrics.date < endOfDay
            }
        )

        let existingMetrics = try modelContext.fetch(descriptor)

        if let metrics = existingMetrics.first {
            // Update existing metrics with calibrated PMC values
            // Store original values for comparison
            let previousCTL = metrics.ctl
            let previousATL = metrics.atl

            // Apply the calibrated values
            metrics.ctl = extractedCTL
            metrics.atl = extractedATL
            // TSB is calculated: TSB = CTL - ATL
            // Note: We don't override this as it should be consistent

            print("[TSSLearning] Updated DailyMetrics PMC:")
            print("  - CTL: \(String(format: "%.1f", previousCTL)) → \(String(format: "%.1f", extractedCTL))")
            print("  - ATL: \(String(format: "%.1f", previousATL)) → \(String(format: "%.1f", extractedATL))")
        } else {
            // Create new DailyMetrics with the PMC values
            let newMetrics = DailyMetrics(date: startOfDay)
            newMetrics.ctl = extractedCTL
            newMetrics.atl = extractedATL
            modelContext.insert(newMetrics)

            print("[TSSLearning] Created new DailyMetrics with PMC: CTL=\(Int(extractedCTL)), ATL=\(Int(extractedATL))")
        }
    }

    /// Get calibration statistics specifically for URL imports
    func getURLImportStatistics() throws -> URLImportStatistics {
        let profile = try fetchScalingProfile()
        let dataPoints = try fetchValidDataPoints()

        // Filter for direct (non-derived) data points which come from URL imports
        let directPoints = dataPoints.filter { $0.derivationMethod == .direct }

        return URLImportStatistics(
            totalSamples: directPoints.count,
            recentSamples: directPoints.filter { $0.ageInDays <= 30 }.count,
            scalingFactor: profile?.globalScalingFactor ?? 1.0,
            confidence: profile?.globalConfidence ?? 0.0,
            perSportCounts: calculatePerSportCounts(dataPoints: directPoints),
            isCalibrationComplete: (profile?.globalConfidence ?? 0) >= 0.95,
            canDisableImport: (profile?.globalSampleCount ?? 0) >= 10 && (profile?.globalConfidence ?? 0) >= 0.9
        )
    }

    /// Calculate per-sport sample counts
    private func calculatePerSportCounts(dataPoints: [TSSCalibrationDataPoint]) -> [ActivityCategory: Int] {
        var counts: [ActivityCategory: Int] = [:]

        for point in dataPoints {
            if let category = point.activityCategory {
                counts[category, default: 0] += 1
            }
        }

        return counts
    }

    // MARK: - Learning Management

    /// Toggle learning on/off
    func setLearningEnabled(_ enabled: Bool) throws {
        let profile = try getOrCreateScalingProfile()
        profile.learningEnabled = enabled
        try modelContext.save()
    }

    /// Reset all learning data
    func resetLearning() throws {
        // Delete all data points
        let dataPointDescriptor = FetchDescriptor<TSSCalibrationDataPoint>()
        let dataPoints = try modelContext.fetch(dataPointDescriptor)
        for point in dataPoints {
            modelContext.delete(point)
        }

        // Reset the profile
        let profile = try getOrCreateScalingProfile()
        profile.globalScalingFactor = 1.0
        profile.globalConfidence = 0.0
        profile.globalSampleCount = 0
        profile.cyclingScalingFactor = nil
        profile.cyclingSampleCount = 0
        profile.runningScalingFactor = nil
        profile.runningSampleCount = 0
        profile.swimScalingFactor = nil
        profile.swimSampleCount = 0
        profile.lastUpdatedAt = Date()

        try modelContext.save()

        print("[TSSLearning] Learning data reset")
    }

    /// Mark a data point as invalid (won't be used in future calculations)
    func invalidateDataPoint(_ dataPoint: TSSCalibrationDataPoint, reason: String) throws {
        dataPoint.isValid = false
        dataPoint.invalidReason = reason

        // Recalculate factors without this point
        if let profile = try fetchScalingProfile() {
            try recalculateScalingFactors(profile: profile)
        }

        try modelContext.save()
    }

    // MARK: - Statistics

    /// Get learning statistics for display
    func getLearningStatistics() throws -> TSSLearningStatistics {
        let profile = try fetchScalingProfile()
        let dataPoints = try fetchValidDataPoints()

        return TSSLearningStatistics(
            scalingFactor: profile?.globalScalingFactor ?? 1.0,
            confidence: profile?.globalConfidence ?? 0.0,
            sampleCount: profile?.globalSampleCount ?? 0,
            learningEnabled: profile?.learningEnabled ?? true,
            canApplyScaling: profile?.canApplyScaling ?? false,
            cyclingFactor: profile?.cyclingScalingFactor,
            cyclingSamples: profile?.cyclingSampleCount ?? 0,
            runningFactor: profile?.runningScalingFactor,
            runningSamples: profile?.runningSampleCount ?? 0,
            swimmingFactor: profile?.swimScalingFactor,
            swimmingSamples: profile?.swimSampleCount ?? 0,
            recentDataPoints: Array(dataPoints.prefix(10))
        )
    }
}

// MARK: - Statistics Result

/// Summary of TSS learning statistics for UI display
struct TSSLearningStatistics {
    let scalingFactor: Double
    let confidence: Double
    let sampleCount: Int
    let learningEnabled: Bool
    let canApplyScaling: Bool

    // Per-sport
    let cyclingFactor: Double?
    let cyclingSamples: Int
    let runningFactor: Double?
    let runningSamples: Int
    let swimmingFactor: Double?
    let swimmingSamples: Int

    let recentDataPoints: [TSSCalibrationDataPoint]

    var scalingPercentage: String {
        String(format: "%.0f%%", (scalingFactor - 1) * 100)
    }

    var confidenceLevel: String {
        switch confidence {
        case 0.9...: return "Very High"
        case 0.7..<0.9: return "High"
        case 0.5..<0.7: return "Medium"
        case 0.3..<0.5: return "Low"
        default: return "Insufficient"
        }
    }

    var statusDescription: String {
        if !learningEnabled {
            return "Learning disabled"
        } else if sampleCount == 0 {
            return "No calibration data yet"
        } else if !canApplyScaling {
            return "Need more data to apply scaling"
        } else {
            return "Active: adjusting TSS by \(scalingPercentage)"
        }
    }
}

// MARK: - URL Import Statistics

/// Statistics for TrainingPeaks URL import calibration
struct URLImportStatistics {
    let totalSamples: Int
    let recentSamples: Int           // Within last 30 days
    let scalingFactor: Double
    let confidence: Double
    let perSportCounts: [ActivityCategory: Int]
    let isCalibrationComplete: Bool
    let canDisableImport: Bool

    /// Minimum samples needed for reliable calibration
    static let minimumSamples = 10

    /// Human-readable scaling description
    var scalingDescription: String {
        if abs(scalingFactor - 1.0) < 0.01 {
            return "TSS matches TrainingPeaks"
        } else if scalingFactor > 1.0 {
            return String(format: "TP is %.0f%% higher", (scalingFactor - 1) * 100)
        } else {
            return String(format: "TP is %.0f%% lower", (1 - scalingFactor) * 100)
        }
    }

    /// Progress towards minimum samples
    var progressToMinimum: Double {
        Double(totalSamples) / Double(Self.minimumSamples)
    }

    /// Samples still needed
    var samplesNeeded: Int {
        max(0, Self.minimumSamples - totalSamples)
    }

    /// Status message for UI
    var statusMessage: String {
        if isCalibrationComplete {
            return "Calibration complete - TSS aligned with TrainingPeaks"
        } else if totalSamples == 0 {
            return "Import workouts from TrainingPeaks to calibrate"
        } else if totalSamples < Self.minimumSamples {
            return "Need \(samplesNeeded) more samples for reliable calibration"
        } else {
            return "Calibrating... \(String(format: "%.0f%%", confidence * 100)) confidence"
        }
    }
}
