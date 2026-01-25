import Foundation
import Vision
import UIKit

/// Service for extracting PMC values from TrainingPeaks screenshots using Vision OCR
actor ScreenshotOCRService {

    // MARK: - OCR Processing

    /// Process a screenshot and extract PMC values
    /// Uses spatial parsing for TrainingPeaks mobile format, falls back to text-based parsing
    func processScreenshot(imageData: Data) async throws -> OCRCalibrationResult {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            print("[OCR] ERROR: Failed to create UIImage/CGImage from data")
            throw OCRError.invalidImage
        }

        print("[OCR] Image loaded: \(cgImage.width)x\(cgImage.height) pixels")

        // Try spatial parsing first (better for TP mobile format)
        do {
            let elements = try await performOCRWithPositions(on: cgImage)
            let rawText = elements.map { $0.text }.joined(separator: "\n")

            print("[OCR] OCR completed, found \(elements.count) text elements")

            // Try spatial parsing first
            if let spatialResult = parseSpatialLayout(elements: elements) {
                print("[OCR] Spatial parsing successful")
                return OCRCalibrationResult(
                    effectiveDate: spatialResult.effectiveDate,
                    ctl: spatialResult.ctl,
                    atl: spatialResult.atl,
                    tsb: spatialResult.tsb,
                    confidence: spatialResult.confidence,
                    rawText: rawText,
                    dailyTSS: spatialResult.dailyTSS,
                    weeklyTSS: nil
                )
            }

            // Fall back to text-based parsing
            print("[OCR] Spatial parsing failed, using text-based parsing")
            return parseCalibrationValues(from: rawText)
        } catch {
            // Fall back to original text-only method
            print("[OCR] Spatial OCR failed, falling back to text-only: \(error)")
            let recognizedText = try await performOCR(on: cgImage)
            return parseCalibrationValues(from: recognizedText)
        }
    }

    /// Process screenshot from file URL
    func processScreenshot(at url: URL) async throws -> OCRCalibrationResult {
        print("[OCR] Processing screenshot from URL: \(url.path)")

        let imageData = try Data(contentsOf: url)
        print("[OCR] Loaded image data: \(imageData.count) bytes")

        return try await processScreenshot(imageData: imageData)
    }

    // MARK: - Vision OCR

    /// Represents a recognized text element with its position
    struct RecognizedTextElement {
        let text: String
        let confidence: Float
        let boundingBox: CGRect  // Normalized coordinates (0-1), origin at bottom-left

        /// Center X position (0-1)
        var centerX: CGFloat { boundingBox.midX }
        /// Center Y position (0-1)
        var centerY: CGFloat { boundingBox.midY }
    }

    private func performOCR(on image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    print("[OCR] Recognition error: \(error)")
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    print("[OCR] No observations returned")
                    continuation.resume(returning: "")
                    return
                }

                print("[OCR] Found \(observations.count) text observations")

                // Log each observation with its bounding box for debugging
                for (index, observation) in observations.enumerated() {
                    if let candidate = observation.topCandidates(1).first {
                        let bbox = observation.boundingBox
                        print("[OCR] [\(index)] '\(candidate.string)' confidence=\(candidate.confidence) bbox=(\(String(format: "%.2f", bbox.minX)), \(String(format: "%.2f", bbox.minY)))")
                    }
                }

                let text = observations.compactMap { observation in
                    observation.topCandidates(1).first?.string
                }.joined(separator: "\n")

                continuation.resume(returning: text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                print("[OCR] Handler error: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }

    /// Perform OCR and return elements with position data
    private func performOCRWithPositions(on image: CGImage) async throws -> [RecognizedTextElement] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let elements = observations.compactMap { observation -> RecognizedTextElement? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return RecognizedTextElement(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: observation.boundingBox
                    )
                }

                continuation.resume(returning: elements)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Process screenshot with spatial awareness for TrainingPeaks mobile format
    func processScreenshotWithSpatialParsing(imageData: Data) async throws -> OCRCalibrationResult {
        guard let image = UIImage(data: imageData),
              let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }

        print("[OCR] Processing with spatial parsing: \(cgImage.width)x\(cgImage.height)")

        let elements = try await performOCRWithPositions(on: cgImage)
        let rawText = elements.map { $0.text }.joined(separator: "\n")

        print("[OCR] Found \(elements.count) text elements")

        // Try spatial parsing first (for TP mobile format)
        if let spatialResult = parseSpatialLayoutWithDebug(elements: elements) {
            print("[OCR] Spatial parsing successful: CTL=\(spatialResult.ctl ?? -1), ATL=\(spatialResult.atl ?? -1), TSB=\(spatialResult.tsb ?? -1)")
            return OCRCalibrationResult(
                effectiveDate: spatialResult.effectiveDate,
                ctl: spatialResult.ctl,
                atl: spatialResult.atl,
                tsb: spatialResult.tsb,
                confidence: spatialResult.confidence,
                rawText: rawText,
                dailyTSS: spatialResult.dailyTSS,
                weeklyTSS: nil,
                debugLog: spatialResult.debugLog
            )
        }

        // Fall back to text-based parsing
        return parseCalibrationValues(from: rawText)
    }

    /// Parse TrainingPeaks mobile format using spatial positions with debug logging
    private func parseSpatialLayoutWithDebug(elements: [RecognizedTextElement]) -> (ctl: Double?, atl: Double?, tsb: Double?, dailyTSS: Double?, effectiveDate: Date?, confidence: Double, debugLog: String)? {
        var debugLines: [String] = []
        debugLines.append("=== Spatial OCR Debug ===")

        let result = parseSpatialLayout(elements: elements, debugLines: &debugLines)

        guard let r = result else {
            debugLines.append("❌ Spatial parsing failed")
            return nil
        }

        return (r.ctl, r.atl, r.tsb, r.dailyTSS, r.effectiveDate, r.confidence, debugLines.joined(separator: "\n"))
    }

    /// Parse TrainingPeaks mobile format using spatial positions (without debug output)
    private func parseSpatialLayout(elements: [RecognizedTextElement]) -> (ctl: Double?, atl: Double?, tsb: Double?, dailyTSS: Double?, effectiveDate: Date?, confidence: Double)? {
        var noDebug: [String] = []
        return parseSpatialLayout(elements: elements, debugLines: &noDebug)
    }

    /// Parse TrainingPeaks mobile format using spatial positions
    /// The TP app shows: [Fitness CTL] [Form TSB] [Fatigue ATL] horizontally
    /// Layout: LEFT = Fitness (43), CENTER = Form (25), RIGHT = Fatigue (19)
    private func parseSpatialLayout(elements: [RecognizedTextElement], debugLines: inout [String]) -> (ctl: Double?, atl: Double?, tsb: Double?, dailyTSS: Double?, effectiveDate: Date?, confidence: Double)?  {

        // STRATEGY: Label-first approach
        // Find the labels (Fitness, Form, Fatigue) and then find numbers ABOVE them
        // In Vision coordinates, Y increases upward, so number above label has HIGHER Y

        // Find label elements
        let fitnessLabels = elements.filter {
            $0.text.lowercased().contains("fitness") || $0.text.lowercased() == "ctl"
        }
        let formLabels = elements.filter {
            $0.text.lowercased().contains("form") || $0.text.lowercased() == "tsb"
        }
        let fatigueLabels = elements.filter {
            $0.text.lowercased().contains("fatigue") || $0.text.lowercased() == "atl"
        }

        print("[OCR] Found labels - Fitness: \(fitnessLabels.count), Form: \(formLabels.count), Fatigue: \(fatigueLabels.count)")
        for label in fitnessLabels {
            print("[OCR]   Fitness label at X=\(String(format: "%.3f", label.centerX)), Y=\(String(format: "%.3f", label.centerY))")
        }
        for label in formLabels {
            print("[OCR]   Form label at X=\(String(format: "%.3f", label.centerX)), Y=\(String(format: "%.3f", label.centerY))")
        }
        for label in fatigueLabels {
            print("[OCR]   Fatigue label at X=\(String(format: "%.3f", label.centerX)), Y=\(String(format: "%.3f", label.centerY))")
        }

        // Find number elements (likely PMC values: 1-200 range)
        let numberElements = elements.compactMap { element -> (element: RecognizedTextElement, value: Double)? in
            var cleaned = element.text
            // Remove arrow characters and other symbols
            for arrow in ["↓", "↑", "⬇", "⬆", "▼", "▲", "↗", "↘", "→", "←", "⬇️", "⬆️", "-", "•"] {
                cleaned = cleaned.replacingOccurrences(of: arrow, with: "")
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

            // Try to extract just the numeric part (allow negative for TSB)
            let pattern = "^([+-]?\\d+)$"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: cleaned, range: NSRange(cleaned.startIndex..., in: cleaned)),
               let range = Range(match.range(at: 1), in: cleaned),
               let value = Double(cleaned[range]) {
                // PMC values typically in 0-200 range, TSB can be negative
                if value >= -50 && value <= 200 {
                    return (element, value)
                }
            }
            return nil
        }

        print("[OCR] Found \(numberElements.count) potential PMC numbers")
        for (elem, val) in numberElements {
            print("[OCR]   Number \(Int(val)) at X=\(String(format: "%.3f", elem.centerX)), Y=\(String(format: "%.3f", elem.centerY))")
        }

        guard !numberElements.isEmpty else { return nil }

        var ctl: Double?
        var atl: Double?
        var tsb: Double?
        var matchCount = 0

        // PRIMARY STRATEGY: Match numbers to labels by X-alignment
        // The number should be at nearly the same X position as its label

        // Helper to find number above a label (same X, higher Y)
        func findNumberAboveLabel(_ label: RecognizedTextElement) -> Double? {
            // Find numbers that are horizontally aligned with this label
            let alignedNumbers = numberElements.filter { (elem, _) in
                let xDiff = abs(elem.centerX - label.centerX)
                // Number should be above label (higher Y in Vision coordinates)
                let isAbove = elem.centerY > label.centerY
                return xDiff < 0.08 && isAbove  // Tight X tolerance
            }

            // Return the closest one vertically
            if let closest = alignedNumbers.min(by: { abs($0.element.centerY - label.centerY) < abs($1.element.centerY - label.centerY) }) {
                print("[OCR]   Found number \(Int(closest.value)) above label '\(label.text)' (xDiff=\(String(format: "%.3f", abs(closest.element.centerX - label.centerX))))")
                return closest.value
            }
            return nil
        }

        // Match Fitness → CTL
        for label in fitnessLabels {
            if let value = findNumberAboveLabel(label) {
                ctl = value
                matchCount += 1
                print("[OCR] Matched CTL=\(Int(value)) from Fitness label")
                break
            }
        }

        // Match Form → TSB
        for label in formLabels {
            if let value = findNumberAboveLabel(label) {
                tsb = value
                matchCount += 1
                print("[OCR] Matched TSB=\(Int(value)) from Form label")
                break
            }
        }

        // Match Fatigue → ATL
        for label in fatigueLabels {
            if let value = findNumberAboveLabel(label) {
                atl = value
                matchCount += 1
                print("[OCR] Matched ATL=\(Int(value)) from Fatigue label")
                break
            }
        }

        // FALLBACK: If label matching didn't work, try row-based approach
        // Sort labels by X to determine column order
        if matchCount < 3 && (fitnessLabels.count > 0 || formLabels.count > 0 || fatigueLabels.count > 0) {
            let allLabels = (fitnessLabels + formLabels + fatigueLabels).sorted { $0.centerX < $1.centerX }

            if allLabels.count >= 2 {
                // Get the Y level of labels
                let labelY = allLabels.map { $0.centerY }.reduce(0, +) / Double(allLabels.count)

                // Find numbers at similar or higher Y (above the labels)
                let pmcNumbers = numberElements
                    .filter { $0.element.centerY >= labelY - 0.05 }  // At or above label level
                    .sorted { $0.element.centerX < $1.element.centerX }

                print("[OCR] Fallback: Found \(pmcNumbers.count) numbers above label level")

                if pmcNumbers.count >= 3 {
                    // Assign based on X position matching labels
                    // Find which number is closest to each label's X position

                    for label in fitnessLabels where ctl == nil {
                        if let closest = pmcNumbers.min(by: { abs($0.element.centerX - label.centerX) < abs($1.element.centerX - label.centerX) }) {
                            ctl = closest.value
                            matchCount += 1
                            print("[OCR] Fallback: CTL=\(Int(closest.value)) nearest to Fitness")
                        }
                    }

                    for label in formLabels where tsb == nil {
                        if let closest = pmcNumbers.min(by: { abs($0.element.centerX - label.centerX) < abs($1.element.centerX - label.centerX) }) {
                            if closest.value != ctl {  // Don't reuse same number
                                tsb = closest.value
                                matchCount += 1
                                print("[OCR] Fallback: TSB=\(Int(closest.value)) nearest to Form")
                            }
                        }
                    }

                    for label in fatigueLabels where atl == nil {
                        if let closest = pmcNumbers.min(by: { abs($0.element.centerX - label.centerX) < abs($1.element.centerX - label.centerX) }) {
                            if closest.value != ctl && closest.value != tsb {
                                atl = closest.value
                                matchCount += 1
                                print("[OCR] Fallback: ATL=\(Int(closest.value)) nearest to Fatigue")
                            }
                        }
                    }
                }
            }
        }

        // Look for TSS value
        var dailyTSS: Double?
        let tssLabels = elements.filter {
            let lower = $0.text.lowercased()
            return lower.contains("tss") || lower.contains("stss") || lower.contains("rtss")
        }
        for tssLabel in tssLabels {
            for (element, value) in numberElements {
                let xDiff = abs(element.centerX - tssLabel.centerX)
                let yDiff = abs(element.centerY - tssLabel.centerY)
                if xDiff < 0.25 && yDiff < 0.15 && value <= 500 {
                    dailyTSS = value
                    print("[OCR] Found TSS=\(Int(value)) near '\(tssLabel.text)'")
                    break
                }
            }
            if dailyTSS != nil { break }
        }

        guard matchCount > 0 else {
            print("[OCR] Spatial parsing failed - no matches found")
            return nil
        }

        let confidence = matchCount >= 3 ? 0.95 : (matchCount == 2 ? 0.75 : 0.5)

        print("[OCR] ✓ Final result: CTL=\(ctl.map { String(Int($0)) } ?? "nil"), TSB=\(tsb.map { String(Int($0)) } ?? "nil"), ATL=\(atl.map { String(Int($0)) } ?? "nil")")
        return (ctl, atl, tsb, dailyTSS, nil, confidence)
    }

    // MARK: - Value Parsing

    /// Parse CTL, ATL, TSB, and TSS values from recognized text
    private func parseCalibrationValues(from text: String) -> OCRCalibrationResult {
        var ctl: Double?
        var atl: Double?
        var tsb: Double?
        var dailyTSS: Double?
        var weeklyTSS: Double?
        var effectiveDate: Date?
        var confidence: Double = 0

        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        var matchCount = 0

        print("[OCR] Parsing \(lines.count) lines of text")
        print("[OCR] Raw text:\n\(text)")

        // First try: Look for number-above-label pattern (TrainingPeaks mobile app style)
        // Format: "44" on one line, "Fitness" on next line
        let trainingPeaksResult = parseTrainingPeaksMobileFormat(lines: lines)
        if trainingPeaksResult.matchCount > 0 {
            ctl = trainingPeaksResult.ctl
            atl = trainingPeaksResult.atl
            tsb = trainingPeaksResult.tsb
            matchCount = trainingPeaksResult.matchCount
            print("[OCR] TrainingPeaks mobile format found: CTL=\(ctl ?? -1), ATL=\(atl ?? -1), TSB=\(tsb ?? -1)")
        }

        // Extract TSS values (daily and weekly)
        let tssResult = parseTSSValues(lines: lines, fullText: text)
        dailyTSS = tssResult.dailyTSS
        weeklyTSS = tssResult.weeklyTSS
        if tssResult.matchCount > 0 {
            print("[OCR] TSS values found: daily=\(dailyTSS ?? -1), weekly=\(weeklyTSS ?? -1)")
        }

        // Second try: Traditional inline patterns
        if matchCount == 0 {
            for line in lines {
                // CTL / Fitness patterns
                if ctl == nil {
                    if let value = extractValue(from: line, patterns: [
                        "ctl[:\\s]+([\\d.]+)",
                        "fitness[:\\s]+([\\d.]+)",
                        "chronic[:\\s]+([\\d.]+)",
                        "([\\d.]+)\\s*ctl"
                    ]) {
                        ctl = value
                        matchCount += 1
                    }
                }

                // ATL / Fatigue patterns
                if atl == nil {
                    if let value = extractValue(from: line, patterns: [
                        "atl[:\\s]+([\\d.]+)",
                        "fatigue[:\\s]+([\\d.]+)",
                        "acute[:\\s]+([\\d.]+)",
                        "([\\d.]+)\\s*atl"
                    ]) {
                        atl = value
                        matchCount += 1
                    }
                }

                // TSB / Form patterns
                if tsb == nil {
                    if let value = extractValue(from: line, patterns: [
                        "tsb[:\\s]+([+-]?[\\d.]+)",
                        "form[:\\s]+([+-]?[\\d.]+)",
                        "balance[:\\s]+([+-]?[\\d.]+)",
                        "([+-]?[\\d.]+)\\s*tsb"
                    ]) {
                        tsb = value
                        matchCount += 1
                    }
                }

                // Date patterns
                if effectiveDate == nil {
                    effectiveDate = extractDate(from: line)
                }
            }
        }

        // Calculate confidence based on matches
        if matchCount >= 3 {
            confidence = 0.95
        } else if matchCount == 2 {
            confidence = 0.75
        } else if matchCount == 1 {
            confidence = 0.5
        } else {
            confidence = 0.2
        }

        // Third try: tabular data patterns
        if ctl == nil && atl == nil && tsb == nil {
            let tableResult = parseTableFormat(from: text)
            if tableResult.isValid {
                ctl = tableResult.ctl
                atl = tableResult.atl
                tsb = tableResult.tsb
                confidence = max(confidence, tableResult.confidence)
            }
        }

        print("[OCR] Final parsed values: CTL=\(ctl ?? -1), ATL=\(atl ?? -1), TSB=\(tsb ?? -1), dailyTSS=\(dailyTSS ?? -1), confidence=\(confidence)")

        return OCRCalibrationResult(
            effectiveDate: effectiveDate,
            ctl: ctl,
            atl: atl,
            tsb: tsb,
            confidence: confidence,
            rawText: text,
            dailyTSS: dailyTSS,
            weeklyTSS: weeklyTSS
        )
    }

    // MARK: - TSS Parsing

    /// Parse daily and weekly TSS values from screenshot text
    private func parseTSSValues(lines: [String], fullText: String) -> (dailyTSS: Double?, weeklyTSS: Double?, matchCount: Int) {
        var dailyTSS: Double?
        var weeklyTSS: Double?
        var matchCount = 0

        // Patterns for daily TSS
        let dailyTSSPatterns = [
            "today[:\\s]+([\\d.]+)\\s*tss",           // "Today: 85 TSS"
            "daily\\s*tss[:\\s]+([\\d.]+)",           // "Daily TSS: 85"
            "tss[:\\s]+([\\d.]+)(?!.*week)",          // "TSS: 85" (not followed by week)
            "([\\d.]+)\\s*tss\\s*today",              // "85 TSS Today"
            "today's\\s*tss[:\\s]+([\\d.]+)"          // "Today's TSS: 85"
        ]

        // Patterns for weekly TSS
        let weeklyTSSPatterns = [
            "weekly\\s*tss[:\\s]+([\\d.]+)",          // "Weekly TSS: 450"
            "7[\\s-]*day\\s*tss[:\\s]+([\\d.]+)",     // "7-day TSS: 450"
            "week[:\\s]+([\\d.]+)\\s*tss",            // "Week: 450 TSS"
            "tss[:\\s]+([\\d.]+).*week",              // "TSS: 450 (week)"
            "([\\d.]+)\\s*tss\\s*(?:this\\s*)?week"   // "450 TSS this week"
        ]

        // Try to extract daily TSS
        for line in lines {
            let lowerLine = line.lowercased()

            // Check daily TSS patterns
            if dailyTSS == nil {
                for pattern in dailyTSSPatterns {
                    if let value = extractValue(from: lowerLine, patterns: [pattern]) {
                        // Validate reasonable range for daily TSS (0-500)
                        if value > 0 && value <= 500 {
                            dailyTSS = value
                            matchCount += 1
                            print("[OCR] Found daily TSS: \(value) from pattern '\(pattern)'")
                            break
                        }
                    }
                }
            }

            // Check weekly TSS patterns
            if weeklyTSS == nil {
                for pattern in weeklyTSSPatterns {
                    if let value = extractValue(from: lowerLine, patterns: [pattern]) {
                        // Validate reasonable range for weekly TSS (0-2000)
                        if value > 0 && value <= 2000 {
                            weeklyTSS = value
                            matchCount += 1
                            print("[OCR] Found weekly TSS: \(value) from pattern '\(pattern)'")
                            break
                        }
                    }
                }
            }
        }

        // Look for TSS in TrainingPeaks mobile format (number above "TSS" label)
        if dailyTSS == nil {
            let tssFromMobileFormat = parseTSSFromMobileFormat(lines: lines)
            if let value = tssFromMobileFormat, value > 0 && value <= 500 {
                dailyTSS = value
                matchCount += 1
                print("[OCR] Found daily TSS from mobile format: \(value)")
            }
        }

        return (dailyTSS, weeklyTSS, matchCount)
    }

    /// Parse TSS from TrainingPeaks mobile format (number above "TSS" label)
    private func parseTSSFromMobileFormat(lines: [String]) -> Double? {
        for (index, line) in lines.enumerated() {
            let lowerLine = line.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

            // Look for lines that are just "TSS" or contain "TSS" as a label
            if lowerLine == "tss" || lowerLine.hasPrefix("tss ") || lowerLine.hasSuffix(" tss") {
                // Check lines before for a number
                let searchRange = max(0, index - 3)..<index
                for searchIndex in searchRange.reversed() {
                    if let value = extractNumber(from: lines[searchIndex]) {
                        if value > 0 && value <= 500 {
                            return value
                        }
                    }
                }
            }
        }
        return nil
    }

    /// Parse TrainingPeaks mobile app format where number appears above label
    /// Format: "44" then "Fitness" on next line (or nearby)
    private func parseTrainingPeaksMobileFormat(lines: [String]) -> (ctl: Double?, atl: Double?, tsb: Double?, matchCount: Int) {
        var ctl: Double?
        var atl: Double?
        var tsb: Double?
        var matchCount = 0

        // Build a map of numbers and their positions
        var numberPositions: [(index: Int, value: Double)] = []

        for (index, line) in lines.enumerated() {
            // Extract number from line, handling various arrow symbols and formatting
            if let value = extractNumber(from: line) {
                numberPositions.append((index: index, value: value))
                print("[OCR] Found number \(value) at line \(index): '\(line)'")
            }
        }

        print("[OCR] Total numbers found: \(numberPositions.count)")

        // For each number, look at surrounding lines for labels
        for (index, value) in numberPositions {
            // Check lines before and after for labels (expanded range to 3)
            let searchRange = max(0, index - 3)...min(lines.count - 1, index + 3)

            for searchIndex in searchRange where searchIndex != index {
                let labelLine = lines[searchIndex].lowercased()

                if ctl == nil && (labelLine.contains("fitness") || labelLine.contains("ctl") || labelLine.contains("chronic")) {
                    ctl = value
                    matchCount += 1
                    print("[OCR] Found CTL/Fitness: \(value) near '\(lines[searchIndex])'")
                    break
                }

                if atl == nil && (labelLine.contains("fatigue") || labelLine.contains("atl") || labelLine.contains("acute")) {
                    atl = value
                    matchCount += 1
                    print("[OCR] Found ATL/Fatigue: \(value) near '\(lines[searchIndex])'")
                    break
                }

                if tsb == nil && (labelLine.contains("form") || labelLine.contains("tsb") || labelLine.contains("balance")) {
                    tsb = value
                    matchCount += 1
                    print("[OCR] Found TSB/Form: \(value) near '\(lines[searchIndex])'")
                    break
                }
            }
        }

        return (ctl, atl, tsb, matchCount)
    }

    /// Extract a number from a line, cleaning various arrow symbols and formatting
    private func extractNumber(from line: String) -> Double? {
        // Remove various arrow characters (Unicode and emoji)
        var cleaned = line
        let arrowPatterns = ["↓", "↑", "→", "←", "⬇", "⬆", "⬇️", "⬆️", "▼", "▲", "↗", "↘", "↙", "↖"]
        for arrow in arrowPatterns {
            cleaned = cleaned.replacingOccurrences(of: arrow, with: "")
        }

        // Remove common suffixes/prefixes
        cleaned = cleaned.replacingOccurrences(of: "TSS", with: "", options: .caseInsensitive)

        // Trim whitespace
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try to parse as number
        if let value = Double(cleaned), value > 0 && value < 500 {
            return value
        }

        // Try regex to extract first number from the string
        let pattern = "([+-]?\\d+\\.?\\d*)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let range = NSRange(cleaned.startIndex..., in: cleaned)
            if let match = regex.firstMatch(in: cleaned, options: [], range: range),
               let swiftRange = Range(match.range(at: 1), in: cleaned) {
                let numberStr = String(cleaned[swiftRange])
                if let value = Double(numberStr), value > 0 && value < 500 {
                    return value
                }
            }
        }

        return nil
    }

    /// Extract numeric value using regex patterns
    private func extractValue(from text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if match.numberOfRanges > 1 {
                    let valueRange = match.range(at: 1)
                    if let swiftRange = Range(valueRange, in: text) {
                        let valueString = String(text[swiftRange])
                        return Double(valueString)
                    }
                }
            }
        }
        return nil
    }

    /// Extract date from text
    private func extractDate(from text: String) -> Date? {
        let datePatterns = [
            "\\d{1,2}/\\d{1,2}/\\d{2,4}",  // MM/DD/YYYY or M/D/YY
            "\\d{4}-\\d{2}-\\d{2}",         // YYYY-MM-DD
            "\\w+ \\d{1,2},? \\d{4}"        // Month DD, YYYY
        ]

        for pattern in datePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                continue
            }

            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let swiftRange = Range(match.range, in: text) {
                let dateString = String(text[swiftRange])
                return parseDate(dateString)
            }
        }

        return nil
    }

    /// Parse date string to Date object
    private func parseDate(_ string: String) -> Date? {
        let formatters = [
            "MM/dd/yyyy",
            "M/d/yyyy",
            "MM/dd/yy",
            "M/d/yy",
            "yyyy-MM-dd",
            "MMMM d, yyyy",
            "MMMM dd, yyyy"
        ]

        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }

        return nil
    }

    /// Parse table-format data (common in TrainingPeaks screenshots)
    private func parseTableFormat(from text: String) -> (ctl: Double?, atl: Double?, tsb: Double?, confidence: Double, isValid: Bool) {
        // Look for patterns like:
        // CTL  ATL  TSB
        // 72   85   -13

        let lines = text.components(separatedBy: .newlines)

        // Find header row
        var headerIndex: Int?
        for (index, line) in lines.enumerated() {
            let upper = line.uppercased()
            if upper.contains("CTL") && upper.contains("ATL") {
                headerIndex = index
                break
            }
        }

        guard let header = headerIndex, header + 1 < lines.count else {
            return (nil, nil, nil, 0, false)
        }

        // Parse the data row (next line after header)
        let dataLine = lines[header + 1]
        let numbers = dataLine.components(separatedBy: .whitespaces)
            .compactMap { Double($0.replacingOccurrences(of: ",", with: "")) }

        guard numbers.count >= 2 else {
            return (nil, nil, nil, 0, false)
        }

        // Determine column order from header
        // Note: Currently using simple assumption that values are in CTL, ATL, TSB order
        // These position variables could be used for more sophisticated column detection
        _ = lines[header].uppercased()

        // Simple assumption: values are in same order as headers
        var ctl: Double?
        var atl: Double?
        var tsb: Double?

        if numbers.count >= 3 {
            ctl = numbers[0]
            atl = numbers[1]
            tsb = numbers[2]
        } else if numbers.count == 2 {
            ctl = numbers[0]
            atl = numbers[1]
        }

        let confidence = numbers.count >= 3 ? 0.8 : 0.6

        return (ctl, atl, tsb, confidence, ctl != nil || atl != nil)
    }
}

// MARK: - Errors

enum OCRError: LocalizedError {
    case invalidImage
    case recognitionFailed
    case noValuesFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not process the image"
        case .recognitionFailed:
            return "Text recognition failed"
        case .noValuesFound:
            return "No PMC values found in the screenshot"
        }
    }
}

// MARK: - App Group Integration

extension ScreenshotOCRService {

    private var appGroupIdentifier: String { "group.com.bobk.FitnessApp" }
    private var sharedImageKey: String { "sharedScreenshot" }

    /// Check if there's a new screenshot from the Share Extension
    func checkForSharedScreenshot() async -> URL? {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print("[ScreenshotOCR] Failed to access UserDefaults for app group: \(appGroupIdentifier)")
            return nil
        }

        guard let filename = userDefaults.string(forKey: sharedImageKey) else {
            // No screenshot shared - this is normal when app opens without sharing
            return nil
        }

        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            print("[ScreenshotOCR] Failed to get container URL for app group: \(appGroupIdentifier)")
            return nil
        }

        let fileURL = containerURL.appendingPathComponent(filename)
        print("[ScreenshotOCR] Checking for file at: \(fileURL.path)")

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[ScreenshotOCR] File does not exist at path: \(fileURL.path)")
            return nil
        }

        print("[ScreenshotOCR] Found shared screenshot: \(fileURL.path)")
        return fileURL
    }

    /// Clear the shared screenshot after processing
    func clearSharedScreenshot() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else { return }

        if let filename = userDefaults.string(forKey: sharedImageKey),
           let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            let fileURL = containerURL.appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: fileURL)
        }

        userDefaults.removeObject(forKey: sharedImageKey)
        userDefaults.removeObject(forKey: "sharedScreenshotDate")
        userDefaults.synchronize()
    }
}
