import Foundation
import SwiftData
import Observation

/// Result of a CSV import operation
struct CSVImportResult: Sendable {
    let totalRows: Int
    let importedCount: Int
    let skippedCount: Int
    let duplicateCount: Int
    let errorCount: Int
    let enrichedCount: Int
    let dateRange: ClosedRange<Date>?
    let errors: [String]

    init(totalRows: Int, importedCount: Int, skippedCount: Int, duplicateCount: Int, errorCount: Int, enrichedCount: Int = 0, dateRange: ClosedRange<Date>?, errors: [String]) {
        self.totalRows = totalRows
        self.importedCount = importedCount
        self.skippedCount = skippedCount
        self.duplicateCount = duplicateCount
        self.errorCount = errorCount
        self.enrichedCount = enrichedCount
        self.dateRange = dateRange
        self.errors = errors
    }

    var summary: String {
        var parts: [String] = []
        if enrichedCount > 0 {
            parts.append("\(enrichedCount) enriched with TSS")
        }
        if importedCount > 0 {
            parts.append("\(importedCount) new workouts")
        }
        if duplicateCount > 0 {
            parts.append("\(duplicateCount) duplicates skipped")
        }
        if skippedCount > 0 {
            parts.append("\(skippedCount) skipped (no TSS)")
        }
        if errorCount > 0 {
            parts.append("\(errorCount) errors")
        }
        return parts.joined(separator: ", ")
    }
}

/// Errors that can occur during CSV import
enum CSVImportError: LocalizedError {
    case fileAccessDenied
    case invalidFileFormat
    case parsingError(String)
    case noValidWorkouts
    case missingRequiredColumns([String])

    var errorDescription: String? {
        switch self {
        case .fileAccessDenied:
            return "Cannot access the selected file"
        case .invalidFileFormat:
            return "The file is not a valid CSV format"
        case .parsingError(let detail):
            return "Error parsing CSV: \(detail)"
        case .noValidWorkouts:
            return "No valid workouts found in the CSV file"
        case .missingRequiredColumns(let columns):
            return "Missing required columns: \(columns.joined(separator: ", "))"
        }
    }
}

/// Service for importing workouts from TrainingPeaks CSV exports
@Observable
@MainActor
final class TPCSVImportService {

    // Import state
    var isImporting = false
    var importProgress: Double = 0
    var currentPhase: ImportPhase = .idle
    var lastResult: CSVImportResult?

    enum ImportPhase {
        case idle
        case reading
        case parsing
        case validating
        case importing
        case complete
        case error

        var description: String {
            switch self {
            case .idle: return "Ready"
            case .reading: return "Reading file..."
            case .parsing: return "Parsing CSV..."
            case .validating: return "Validating workouts..."
            case .importing: return "Importing workouts..."
            case .complete: return "Import complete"
            case .error: return "Import failed"
            }
        }
    }

    // MARK: - CSV Parsing

    /// Parse a TrainingPeaks CSV file into workout imports
    /// - Parameter url: URL to the CSV file
    /// - Returns: Array of parsed workouts
    func parseCSV(from url: URL) async throws -> [TPWorkoutImport] {
        currentPhase = .reading

        // Start secure access for files from document picker
        guard url.startAccessingSecurityScopedResource() else {
            throw CSVImportError.fileAccessDenied
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Read file contents
        let content: String
        do {
            content = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw CSVImportError.parsingError("Could not read file: \(error.localizedDescription)")
        }

        currentPhase = .parsing

        // Parse CSV
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count > 1 else {
            throw CSVImportError.invalidFileFormat
        }

        // Parse header row
        let headers = parseCSVLine(lines[0])

        // Validate required columns
        let requiredColumns = ["WorkoutDay", "WorkoutType"]
        let missingColumns = requiredColumns.filter { !headers.contains($0) }
        if !missingColumns.isEmpty {
            throw CSVImportError.missingRequiredColumns(missingColumns)
        }

        // Create date formatter for TrainingPeaks format (typically YYYY-MM-DD)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // Alternative date formats to try
        let alternateFormatters: [DateFormatter] = [
            {
                // 2-digit year format (1/2/25 -> Jan 2, 2025)
                let f = DateFormatter()
                f.dateFormat = "M/d/yy"
                f.locale = Locale(identifier: "en_US_POSIX")
                // Ensure 2-digit years are interpreted as 2000s, not 1900s
                f.twoDigitStartDate = Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1))
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "M/d/yyyy"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "MM/dd/yyyy"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                // Single digit month/day format (2025-2-25)
                let f = DateFormatter()
                f.dateFormat = "yyyy-M-d"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }()
        ]

        // Parse data rows
        var workouts: [TPWorkoutImport] = []
        let totalRows = lines.count - 1

        for (index, line) in lines.dropFirst().enumerated() {
            importProgress = Double(index) / Double(totalRows)

            let values = parseCSVLine(line)
            guard values.count == headers.count else { continue }

            // Create dictionary from headers and values
            var rowDict: [String: String] = [:]
            for (header, value) in zip(headers, values) {
                rowDict[header] = value
            }

            // Try to parse with primary formatter first, then alternatives
            if let workout = TPWorkoutImport.from(csvRow: rowDict, dateFormatter: dateFormatter) {
                workouts.append(workout)
            } else {
                // Try alternate date formats
                for altFormatter in alternateFormatters {
                    if let workout = TPWorkoutImport.from(csvRow: rowDict, dateFormatter: altFormatter) {
                        workouts.append(workout)
                        break
                    }
                }
            }
        }

        guard !workouts.isEmpty else {
            throw CSVImportError.noValidWorkouts
        }

        print("[TPCSVImport] Parsed \(workouts.count) workouts from CSV")
        return workouts
    }

    /// Parse a single CSV line, handling quoted values
    private func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var currentValue = ""
        var insideQuotes = false

        for char in line {
            switch char {
            case "\"":
                insideQuotes.toggle()
            case ",":
                if insideQuotes {
                    currentValue.append(char)
                } else {
                    result.append(currentValue.trimmingCharacters(in: .whitespaces))
                    currentValue = ""
                }
            default:
                currentValue.append(char)
            }
        }

        // Add the last value
        result.append(currentValue.trimmingCharacters(in: .whitespaces))

        return result
    }

    // MARK: - Import to Database

    /// Import parsed workouts into the database
    /// - Parameters:
    ///   - workouts: Parsed workout data from CSV
    ///   - context: SwiftData model context
    /// - Returns: Import result with statistics
    func importWorkouts(_ workouts: [TPWorkoutImport], into context: ModelContext) async throws -> CSVImportResult {
        isImporting = true
        currentPhase = .validating
        importProgress = 0

        defer {
            isImporting = false
        }

        // Fetch existing workouts for duplicate detection
        let descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let existingWorkouts = (try? context.fetch(descriptor)) ?? []

        // Create a set of existing workout identifiers (date + duration + type)
        let existingIdentifiers = Set(existingWorkouts.map { workout -> String in
            let dateKey = Calendar.current.startOfDay(for: workout.startDate).timeIntervalSince1970
            return "\(dateKey)_\(workout.activityCategory.rawValue)_\(Int(workout.durationSeconds))"
        })

        currentPhase = .importing

        var importedCount = 0
        var skippedCount = 0
        var duplicateCount = 0
        var errorCount = 0
        var errors: [String] = []
        var dates: [Date] = []

        let totalWorkouts = workouts.count

        for (index, tpWorkout) in workouts.enumerated() {
            importProgress = Double(index) / Double(totalWorkouts)

            // Skip workouts without TSS (they provide no training load value)
            guard let tss = tpWorkout.tss, tss > 0 else {
                skippedCount += 1
                continue
            }

            // Check for duplicates
            let dateKey = Calendar.current.startOfDay(for: tpWorkout.workoutDay).timeIntervalSince1970
            let duration = tpWorkout.durationSeconds ?? 0
            let identifier = "\(dateKey)_\(tpWorkout.activityCategory.rawValue)_\(Int(duration))"

            if existingIdentifiers.contains(identifier) {
                duplicateCount += 1
                continue
            }

            // Create WorkoutRecord from TP data
            let workoutRecord = mapToWorkoutRecord(tpWorkout)

            context.insert(workoutRecord)
            importedCount += 1
            dates.append(workoutRecord.startDate)
        }

        // Save all imports
        do {
            try context.save()
        } catch {
            throw CSVImportError.parsingError("Failed to save: \(error.localizedDescription)")
        }

        currentPhase = .complete
        importProgress = 1.0

        // Calculate date range
        let dateRange: ClosedRange<Date>?
        if let minDate = dates.min(), let maxDate = dates.max() {
            dateRange = minDate...maxDate
        } else {
            dateRange = nil
        }

        let result = CSVImportResult(
            totalRows: workouts.count,
            importedCount: importedCount,
            skippedCount: skippedCount,
            duplicateCount: duplicateCount,
            errorCount: errorCount,
            dateRange: dateRange,
            errors: errors
        )

        lastResult = result
        print("[TPCSVImport] Import complete: \(result.summary)")

        return result
    }

    // MARK: - Mapping

    /// Convert a TPWorkoutImport to a WorkoutRecord
    func mapToWorkoutRecord(_ tp: TPWorkoutImport) -> WorkoutRecord {
        let duration = tp.durationSeconds ?? 0
        let startDate = tp.workoutDay
        let endDate = startDate.addingTimeInterval(duration)

        let record = WorkoutRecord(
            healthKitUUID: nil, // Not from HealthKit
            activityType: tp.workoutType,
            activityCategory: tp.activityCategory,
            title: tp.title,
            startDate: startDate,
            endDate: endDate,
            durationSeconds: duration,
            distanceMeters: tp.distanceMeters,
            tss: tp.tss ?? 0,
            tssType: .trainingPeaks,
            intensityFactor: tp.intensityFactor ?? 0,
            indoorWorkout: false,
            hasRoute: false
        )

        // Set power data
        record.averagePower = tp.powerAverage
        record.normalizedPower = tp.powerNormalized
        record.maxPower = tp.powerMax

        // Set heart rate data
        record.averageHeartRate = tp.heartRateAverage
        record.maxHeartRate = tp.heartRateMax

        // Set cadence
        record.averageCadence = tp.cadenceAverage

        // Set elevation
        record.totalAscent = tp.elevationGain
        record.totalDescent = tp.elevationLoss

        // Set calories
        record.activeCalories = tp.calories

        // Set HR zone distribution (minutes per zone)
        if tp.totalHRZoneMinutes > 0 {
            var hrDistribution: [String: Double] = [:]
            for (index, minutes) in tp.hrZones.enumerated() {
                if minutes > 0 {
                    hrDistribution["zone\(index + 1)"] = minutes
                }
            }
            record.heartRateZoneDistribution = hrDistribution
        }

        // Set power zone distribution (minutes per zone)
        if tp.totalPowerZoneMinutes > 0 {
            var powerDistribution: [String: Double] = [:]
            for (index, minutes) in tp.powerZones.enumerated() {
                if minutes > 0 {
                    powerDistribution["zone\(index + 1)"] = minutes
                }
            }
            record.powerZoneDistribution = powerDistribution
        }

        // Set subjective data
        record.rpe = tp.rpe
        record.feeling = tp.feeling
        if let athleteComments = tp.athleteComments, !athleteComments.isEmpty {
            record.notes = athleteComments
        }
        record.coachComments = tp.coachComments

        // Set source
        record.source = .trainingPeaks

        return record
    }

    // MARK: - TSS Enrichment Import

    /// Import TP CSV as TSS enrichment for existing Strava-created workouts.
    /// For each TP workout:
    /// - Match to existing workout: same calendar day, same activity category, duration within 15%
    /// - If match found: update TSS, IF, zone distributions, RPE, feeling, comments
    /// - If no match: create new WorkoutRecord (for TP-only workouts)
    func enrichImport(_ workouts: [TPWorkoutImport], into context: ModelContext) async throws -> CSVImportResult {
        isImporting = true
        currentPhase = .validating
        importProgress = 0

        defer { isImporting = false }

        // Fetch all existing workouts for matching
        let descriptor = FetchDescriptor<WorkoutRecord>(
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let existingWorkouts = (try? context.fetch(descriptor)) ?? []

        currentPhase = .importing

        var enrichedCount = 0
        var newCount = 0
        var skippedCount = 0
        var errors: [String] = []
        var dates: [Date] = []

        let totalWorkouts = workouts.count

        for (index, tpWorkout) in workouts.enumerated() {
            importProgress = Double(index) / Double(max(totalWorkouts, 1))

            guard let tss = tpWorkout.tss, tss > 0 else {
                skippedCount += 1
                continue
            }

            // Try to find a matching existing workout
            if let match = findMatchingWorkout(for: tpWorkout, in: existingWorkouts) {
                enrichWorkout(match, with: tpWorkout)
                enrichedCount += 1
                dates.append(match.startDate)
            } else {
                // No match - create new WorkoutRecord for TP-only workouts
                let record = mapToWorkoutRecord(tpWorkout)
                context.insert(record)
                newCount += 1
                dates.append(record.startDate)
            }
        }

        do {
            try context.save()
        } catch {
            throw CSVImportError.parsingError("Failed to save: \(error.localizedDescription)")
        }

        currentPhase = .complete
        importProgress = 1.0

        let dateRange: ClosedRange<Date>?
        if let minDate = dates.min(), let maxDate = dates.max() {
            dateRange = minDate...maxDate
        } else {
            dateRange = nil
        }

        let result = CSVImportResult(
            totalRows: workouts.count,
            importedCount: newCount,
            skippedCount: skippedCount,
            duplicateCount: 0,
            errorCount: errors.count,
            enrichedCount: enrichedCount,
            dateRange: dateRange,
            errors: errors
        )

        lastResult = result
        print("[TPCSVImport] Enrichment complete: \(result.summary)")
        return result
    }

    /// Find a matching existing workout for a TP workout
    /// Criteria: same calendar day, same activity category, duration within 15%
    private func findMatchingWorkout(for tpWorkout: TPWorkoutImport, in workouts: [WorkoutRecord]) -> WorkoutRecord? {
        let tpDay = Calendar.current.startOfDay(for: tpWorkout.workoutDay)
        let tpDuration = tpWorkout.durationSeconds ?? 0
        let tpCategory = tpWorkout.activityCategory

        return workouts.first { workout in
            let workoutDay = Calendar.current.startOfDay(for: workout.startDate)
            guard workoutDay == tpDay else { return false }
            guard workout.activityCategory == tpCategory else { return false }

            // Duration within 15% (TP and Strava may differ slightly)
            guard tpDuration > 0, workout.durationSeconds > 0 else { return true }
            let durationDiff = abs(workout.durationSeconds - tpDuration) / max(tpDuration, 1)
            return durationDiff <= 0.15
        }
    }

    /// Enrich an existing workout with TP CSV data (TSS, zones, subjective data)
    private func enrichWorkout(_ workout: WorkoutRecord, with tp: TPWorkoutImport) {
        // Update TSS from TrainingPeaks (authoritative source)
        if let tss = tp.tss, tss > 0 {
            workout.tss = tss
            workout.tssType = .trainingPeaks
        }

        if let ifValue = tp.intensityFactor, ifValue > 0 {
            workout.intensityFactor = ifValue
        }

        // Update power data if available
        if let np = tp.powerNormalized { workout.normalizedPower = np }
        if let avgPower = tp.powerAverage { workout.averagePower = avgPower }
        if let maxPower = tp.powerMax { workout.maxPower = maxPower }

        // Update HR zone distribution
        if tp.totalHRZoneMinutes > 0 {
            var hrDistribution: [String: Double] = [:]
            for (index, minutes) in tp.hrZones.enumerated() {
                if minutes > 0 {
                    hrDistribution["zone\(index + 1)"] = minutes
                }
            }
            workout.heartRateZoneDistribution = hrDistribution
        }

        // Update power zone distribution
        if tp.totalPowerZoneMinutes > 0 {
            var powerDistribution: [String: Double] = [:]
            for (index, minutes) in tp.powerZones.enumerated() {
                if minutes > 0 {
                    powerDistribution["zone\(index + 1)"] = minutes
                }
            }
            workout.powerZoneDistribution = powerDistribution
        }

        // Update subjective data
        if let rpe = tp.rpe { workout.rpe = rpe }
        if let feeling = tp.feeling { workout.feeling = feeling }
        if let comments = tp.athleteComments, !comments.isEmpty {
            workout.notes = comments
        }
        if let coachComments = tp.coachComments, !coachComments.isEmpty {
            workout.coachComments = coachComments
        }

        // Mark as enriched with TP data but keep pending for verification
        workout.updatedAt = Date()
        print("[TPCSVImport] Enriched '\(workout.title ?? "Untitled")' with TP TSS: \(tp.tss ?? 0)")
    }

    // MARK: - Preview

    /// Generate a preview of workouts to be imported (without actually importing)
    func previewImport(_ workouts: [TPWorkoutImport], existingWorkouts: [WorkoutRecord]) -> CSVImportPreview {
        let existingIdentifiers = Set(existingWorkouts.map { workout -> String in
            let dateKey = Calendar.current.startOfDay(for: workout.startDate).timeIntervalSince1970
            return "\(dateKey)_\(workout.activityCategory.rawValue)_\(Int(workout.durationSeconds))"
        })

        var newWorkouts: [TPWorkoutImport] = []
        var duplicates: [TPWorkoutImport] = []
        var skipped: [TPWorkoutImport] = []

        for workout in workouts {
            // Skip workouts without TSS
            guard let tss = workout.tss, tss > 0 else {
                skipped.append(workout)
                continue
            }

            // Check for duplicates
            let dateKey = Calendar.current.startOfDay(for: workout.workoutDay).timeIntervalSince1970
            let duration = workout.durationSeconds ?? 0
            let identifier = "\(dateKey)_\(workout.activityCategory.rawValue)_\(Int(duration))"

            if existingIdentifiers.contains(identifier) {
                duplicates.append(workout)
            } else {
                newWorkouts.append(workout)
            }
        }

        // Calculate stats by category
        var byCategory: [ActivityCategory: Int] = [:]
        var totalTSS: Double = 0
        for workout in newWorkouts {
            byCategory[workout.activityCategory, default: 0] += 1
            totalTSS += workout.tss ?? 0
        }

        // Date range
        let dates = newWorkouts.map { $0.workoutDay }
        let dateRange: ClosedRange<Date>?
        if let minDate = dates.min(), let maxDate = dates.max() {
            dateRange = minDate...maxDate
        } else {
            dateRange = nil
        }

        return CSVImportPreview(
            newWorkoutsCount: newWorkouts.count,
            duplicatesCount: duplicates.count,
            skippedCount: skipped.count,
            byCategory: byCategory,
            totalTSS: totalTSS,
            dateRange: dateRange
        )
    }
}

/// Preview data for CSV import
struct CSVImportPreview {
    let newWorkoutsCount: Int
    let duplicatesCount: Int
    let skippedCount: Int
    let byCategory: [ActivityCategory: Int]
    let totalTSS: Double
    let dateRange: ClosedRange<Date>?

    var isEmpty: Bool {
        newWorkoutsCount == 0
    }

    var dateRangeFormatted: String? {
        guard let range = dateRange else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: range.lowerBound)) - \(formatter.string(from: range.upperBound))"
    }
}
