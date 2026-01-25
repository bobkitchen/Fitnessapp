import SwiftUI
import SwiftData

/// View for reviewing and applying calibration from TrainingPeaks screenshots
struct CalibrationReviewView: View {
    let screenshotURL: URL?
    @Binding var calibrationResult: CalibrationRecord?
    let onDismiss: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [WorkoutRecord]
    @Query(sort: \DailyMetrics.date, order: .reverse) private var dailyMetrics: [DailyMetrics]

    @State private var isProcessing = true
    @State private var ocrResult: OCRCalibrationResult?
    @State private var errorMessage: String?
    @State private var showingHistory = false
    @State private var showingDebugInfo = false

    // Calculated values
    @State private var calculatedCTL: Double = 0
    @State private var calculatedATL: Double = 0
    @State private var calculatedTSB: Double = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    if isProcessing {
                        processingView
                    } else if let error = errorMessage {
                        errorView(error)
                    } else if let ocr = ocrResult, ocr.isValid {
                        resultsView(ocr)
                    } else {
                        noResultsView
                    }
                }
                .padding()
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundStyle(Color.textSecondary)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingHistory = true
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .foregroundStyle(Color.accentPrimary)
                }
            }
            .sheet(isPresented: $showingHistory) {
                CalibrationHistoryView()
            }
        }
        .task {
            await processScreenshot()
        }
    }

    // MARK: - Processing View

    private var processingView: some View {
        VStack(spacing: Spacing.lg) {
            Spacer()

            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.accentPrimary)

            Text("Processing Screenshot...")
                .font(AppFont.labelLarge)
                .foregroundStyle(Color.textPrimary)

            Text("Extracting PMC values using OCR")
                .font(AppFont.captionLarge)
                .foregroundStyle(Color.textTertiary)

            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.statusLow)

            Text("Processing Failed")
                .font(AppFont.titleLarge)
                .foregroundStyle(Color.textPrimary)

            Text(error)
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            Button("Dismiss") {
                onDismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, Spacing.md)
        }
        .padding(Spacing.xl)
    }

    // MARK: - No Results View

    private var noResultsView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)

            Text("No PMC Values Found")
                .font(AppFont.titleLarge)
                .foregroundStyle(Color.textPrimary)

            Text("The screenshot doesn't appear to contain CTL, ATL, or TSB values. Make sure you're sharing a PMC chart from TrainingPeaks.")
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)

            Button("Dismiss") {
                onDismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, Spacing.md)
        }
        .padding(Spacing.xl)
    }

    // MARK: - Results View

    private func resultsView(_ ocr: OCRCalibrationResult) -> some View {
        VStack(spacing: Spacing.lg) {
            // Screenshot preview
            if let url = screenshotURL,
               let imageData = try? Data(contentsOf: url),
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
                    .overlay(
                        RoundedRectangle(cornerRadius: CornerRadius.medium)
                            .stroke(Color.borderPrimary, lineWidth: 1)
                    )
            }

            // Confidence indicator
            confidenceIndicator(ocr.confidence)

            // Values comparison
            valuesComparisonCard(ocr)

            // Debug info (tap to expand)
            debugInfoSection(ocr)

            // Delta summary
            if needsCalibration(ocr) {
                deltaSummaryCard(ocr)
            }

            // Action buttons
            actionButtons(ocr)
        }
    }

    // MARK: - Debug Info Section

    private func debugInfoSection(_ ocr: OCRCalibrationResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Button {
                withAnimation {
                    showingDebugInfo.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "ladybug")
                        .foregroundStyle(Color.textTertiary)
                    Text("OCR Debug Info")
                        .font(AppFont.labelSmall)
                        .foregroundStyle(Color.textTertiary)
                    Spacer()
                    Image(systemName: showingDebugInfo ? "chevron.up" : "chevron.down")
                        .foregroundStyle(Color.textTertiary)
                        .font(.caption)
                }
            }

            if showingDebugInfo {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    // Show what was detected
                    Group {
                        Text("Detected Values:")
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.textSecondary)

                        Text("CTL → \(ocr.ctl.map { String(Int($0)) } ?? "nil")")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.accentPrimary)

                        Text("ATL → \(ocr.atl.map { String(Int($0)) } ?? "nil")")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.accentPrimary)

                        Text("TSB → \(ocr.tsb.map { String(Int($0)) } ?? "nil")")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.accentPrimary)
                    }

                    Divider()
                        .background(Color.borderPrimary)

                    // Show raw OCR text
                    Text("Raw OCR Text:")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textSecondary)
                        .padding(.top, Spacing.xs)

                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(ocr.rawText ?? "No raw text")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Color.textTertiary)
                            .lineLimit(nil)
                    }
                    .frame(maxHeight: 100)

                    // Parse raw text to show detected numbers
                    let numbers = extractNumbersFromRawText(ocr.rawText ?? "")
                    if !numbers.isEmpty {
                        Divider()
                            .background(Color.borderPrimary)

                        Text("Numbers found in text:")
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.textSecondary)

                        Text(numbers.map { String(Int($0)) }.joined(separator: ", "))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Color.statusModerate)
                    }

                    // Expected values hint
                    Divider()
                        .background(Color.borderPrimary)

                    Text("Expected (from screenshot):")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textSecondary)

                    Text("CTL=43, TSB=25, ATL=19")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Color.statusGood)
                }
                .padding(Spacing.sm)
                .background(Color.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            }
        }
        .padding(Spacing.sm)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    /// Extract numbers from raw OCR text for debug display
    private func extractNumbersFromRawText(_ text: String) -> [Double] {
        let pattern = "\\b(\\d+)\\b"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        return matches.compactMap { match -> Double? in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            let numStr = String(text[range])
            guard let value = Double(numStr), value >= 1 && value <= 200 else { return nil }
            return value
        }
    }

    private func confidenceIndicator(_ confidence: Double) -> some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(confidenceColor(confidence))
                .frame(width: 10, height: 10)

            Text("OCR Confidence: \(confidenceLabel(confidence))")
                .font(AppFont.labelMedium)
                .foregroundStyle(Color.textSecondary)

            Spacer()

            Text("\(Int(confidence * 100))%")
                .font(AppFont.metricSmall.monospacedDigit())
                .foregroundStyle(confidenceColor(confidence))
        }
        .padding(Spacing.md)
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private func valuesComparisonCard(_ ocr: OCRCalibrationResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("VALUES COMPARISON")
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)

            HStack {
                Spacer()
                Text("Extracted")
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 80)
                Text("Calculated")
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 80)
                Text("Delta")
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 60)
            }

            Divider()
                .background(Color.borderPrimary)

            // CTL Row
            valueRow(
                label: "CTL (Fitness)",
                extracted: ocr.ctl,
                calculated: calculatedCTL
            )

            // ATL Row
            valueRow(
                label: "ATL (Fatigue)",
                extracted: ocr.atl,
                calculated: calculatedATL
            )

            // TSB Row
            valueRow(
                label: "TSB (Form)",
                extracted: ocr.tsb,
                calculated: calculatedTSB
            )
        }
        .padding(Spacing.md)
        .cardBackground()
    }

    private func valueRow(label: String, extracted: Double?, calculated: Double) -> some View {
        HStack {
            Text(label)
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            if let ext = extracted {
                Text("\(Int(ext))")
                    .font(AppFont.metricSmall.monospacedDigit())
                    .foregroundStyle(Color.accentPrimary)
                    .frame(width: 80)

                Text("\(Int(calculated))")
                    .font(AppFont.metricSmall.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 80)

                let delta = ext - calculated
                Text(delta >= 0 ? "+\(Int(delta))" : "\(Int(delta))")
                    .font(AppFont.labelMedium.monospacedDigit())
                    .foregroundStyle(deltaColor(delta))
                    .frame(width: 60)
            } else {
                Text("—")
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 80)

                Text("\(Int(calculated))")
                    .font(AppFont.metricSmall.monospacedDigit())
                    .foregroundStyle(Color.textSecondary)
                    .frame(width: 80)

                Text("—")
                    .font(AppFont.labelMedium)
                    .foregroundStyle(Color.textTertiary)
                    .frame(width: 60)
            }
        }
    }

    private func deltaSummaryCard(_ ocr: OCRCalibrationResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.xs) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.statusModerate)

                Text("CALIBRATION RECOMMENDED")
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.statusModerate)
            }

            Text("The extracted values differ significantly from calculated values. Applying calibration will adjust your PMC to match TrainingPeaks.")
                .font(AppFont.captionLarge)
                .foregroundStyle(Color.textSecondary)
        }
        .padding(Spacing.md)
        .background(Color.statusModerate.opacity(0.1))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(Color.statusModerate.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private func actionButtons(_ ocr: OCRCalibrationResult) -> some View {
        VStack(spacing: Spacing.md) {
            Button {
                applyCalibration(ocr)
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                    Text("Apply Calibration")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
                onDismiss()
            } label: {
                Text("Dismiss")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .padding(.top, Spacing.md)
    }

    // MARK: - Processing

    private func processScreenshot() async {
        guard let url = screenshotURL else {
            errorMessage = "No screenshot provided"
            isProcessing = false
            return
        }

        // Calculate current PMC values
        await calculateCurrentPMC()

        // Process OCR
        let ocrService = ScreenshotOCRService()
        do {
            let result = try await ocrService.processScreenshot(at: url)
            await MainActor.run {
                ocrResult = result
                isProcessing = false
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                isProcessing = false
            }
        }
    }

    private func calculateCurrentPMC() async {
        let calendar = Calendar.current
        let endDate = Date()
        let startDate = calendar.date(byAdding: .month, value: -6, to: endDate)!

        let pmcData = PMCCalculator.calculatePMC(
            workouts: workouts,
            startDate: startDate,
            endDate: endDate
        )

        await MainActor.run {
            if let latest = pmcData.last {
                calculatedCTL = latest.ctl
                calculatedATL = latest.atl
                calculatedTSB = latest.tsb
            }
        }
    }

    private func applyCalibration(_ ocr: OCRCalibrationResult) {
        // Create calibration record
        let record = CalibrationRecord(
            effectiveDate: ocr.effectiveDate ?? Date(),
            extractedCTL: ocr.ctl,
            extractedATL: ocr.atl,
            extractedTSB: ocr.tsb,
            calculatedCTL: calculatedCTL,
            calculatedATL: calculatedATL,
            calculatedTSB: calculatedTSB,
            ocrConfidence: ocr.confidence,
            sourceType: .screenshot
        )
        record.ocrRawText = ocr.rawText
        record.calibrationApplied = true
        record.calibrationNote = "Applied from TrainingPeaks screenshot"

        // Apply to most recent daily metrics if available
        if let todayMetrics = dailyMetrics.first {
            record.applyTo(todayMetrics)
        }

        // Save
        modelContext.insert(record)
        try? modelContext.save()

        calibrationResult = record
        onDismiss()
    }

    // MARK: - Helpers

    private func needsCalibration(_ ocr: OCRCalibrationResult) -> Bool {
        let threshold = 5.0
        if let ctl = ocr.ctl, abs(ctl - calculatedCTL) > threshold { return true }
        if let atl = ocr.atl, abs(atl - calculatedATL) > threshold { return true }
        if let tsb = ocr.tsb, abs(tsb - calculatedTSB) > threshold { return true }
        return false
    }

    private func confidenceColor(_ confidence: Double) -> Color {
        switch confidence {
        case 0.9...: return .statusExcellent
        case 0.7..<0.9: return .statusGood
        case 0.5..<0.7: return .statusModerate
        default: return .statusLow
        }
    }

    private func confidenceLabel(_ confidence: Double) -> String {
        switch confidence {
        case 0.9...: return "High"
        case 0.7..<0.9: return "Medium"
        case 0.5..<0.7: return "Low"
        default: return "Very Low"
        }
    }

    private func deltaColor(_ delta: Double) -> Color {
        if abs(delta) < 5 {
            return .statusGood
        } else if abs(delta) < 15 {
            return .statusModerate
        } else {
            return .statusLow
        }
    }
}

// MARK: - Button Styles

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.labelLarge)
            .foregroundStyle(.white)
            .padding(.vertical, Spacing.md)
            .background(Color.accentPrimary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.labelLarge)
            .foregroundStyle(Color.textSecondary)
            .padding(.vertical, Spacing.md)
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.large)
                    .stroke(Color.borderPrimary, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// MARK: - Calibration History View

struct CalibrationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CalibrationRecord.processedAt, order: .reverse) private var calibrations: [CalibrationRecord]

    var body: some View {
        NavigationStack {
            Group {
                if calibrations.isEmpty {
                    emptyStateView
                } else {
                    calibrationList
                }
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Calibration History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.accentPrimary)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(Color.textTertiary)

            Text("No Calibrations Yet")
                .font(AppFont.titleLarge)
                .foregroundStyle(Color.textPrimary)

            Text("Share a TrainingPeaks PMC screenshot to calibrate your fitness metrics.")
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.xl)
        }
    }

    private var calibrationList: some View {
        List {
            ForEach(calibrations) { calibration in
                CalibrationRowView(calibration: calibration)
                    .listRowBackground(Color.backgroundSecondary)
            }
            .onDelete(perform: deleteCalibrations)
        }
        .scrollContentBackground(.hidden)
    }

    private func deleteCalibrations(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(calibrations[index])
        }
        try? modelContext.save()
    }
}

struct CalibrationRowView: View {
    let calibration: CalibrationRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(calibration.effectiveDate, style: .date)
                    .font(AppFont.labelMedium)
                    .foregroundStyle(Color.textPrimary)

                Spacer()

                if calibration.calibrationApplied {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.statusGood)
                } else {
                    Label("Skipped", systemImage: "xmark.circle")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Text(calibration.deltaSummary)
                .font(AppFont.captionLarge)
                .foregroundStyle(Color.textSecondary)

            HStack {
                Text(calibration.sourceType.rawValue)
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)

                Spacer()

                Text("\(calibration.confidenceLevel) confidence")
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Preview

#Preview {
    CalibrationReviewView(
        screenshotURL: nil,
        calibrationResult: .constant(nil),
        onDismiss: {}
    )
    .modelContainer(for: [
        CalibrationRecord.self,
        WorkoutRecord.self,
        DailyMetrics.self
    ], inMemory: true)
}
