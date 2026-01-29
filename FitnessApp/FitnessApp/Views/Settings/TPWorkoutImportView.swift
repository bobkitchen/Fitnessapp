import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// View for importing workouts from TrainingPeaks CSV (TSS enrichment for existing Strava workouts)
struct TPWorkoutImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // CSV Import state
    @State private var showingFilePicker = false
    @State private var csvImportService = TPCSVImportService()
    @State private var parsedWorkouts: [TPWorkoutImport] = []
    @State private var csvPreview: CSVImportPreview?
    @State private var csvImportResult: CSVImportResult?
    @State private var csvError: String?

    // Ignored - kept for compatibility with Share Extension launch
    var prefilledURL: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    csvImportSection
                }
                .padding()
            }
            .navigationTitle("Import TrainingPeaks CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
        }
    }

    // MARK: - CSV Import Section

    @ViewBuilder
    private var csvImportSection: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.blue)

                Text("Enrich Workouts with TSS")
                    .font(.headline)

                Text("Import your TrainingPeaks CSV to add accurate TSS, IF, training zones, and coach comments to your existing Strava workouts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // File selection
            Button {
                showingFilePicker = true
            } label: {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text(parsedWorkouts.isEmpty ? "Select CSV File" : "Select Different File")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            // Preview section
            if let preview = csvPreview {
                csvPreviewCard(preview)
            }

            // Import progress
            if csvImportService.isImporting {
                csvProgressCard
            }

            // Import result
            if let result = csvImportResult {
                csvResultCard(result)
            }

            // Error
            if let error = csvError {
                errorCard(message: error)
            }

            // How to export instructions
            howToExportSection
        }
    }

    @ViewBuilder
    private func csvPreviewCard(_ preview: CSVImportPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "eye.fill")
                    .foregroundStyle(.blue)
                Text("Preview")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
            }

            Divider()

            // Stats
            HStack(spacing: 16) {
                StatItem(value: "\(preview.newWorkoutsCount + preview.duplicatesCount)", label: "Workouts", icon: "figure.mixed.cardio")
                StatItem(value: String(format: "%.0f", preview.totalTSS), label: "Total TSS", icon: "bolt.fill")
            }

            // Date range
            if let range = preview.dateRangeFormatted {
                HStack {
                    Image(systemName: "calendar")
                        .foregroundStyle(.secondary)
                    Text(range)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // By category
            if !preview.byCategory.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(preview.byCategory.sorted { $0.value > $1.value }), id: \.key) { category, count in
                        HStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .foregroundStyle(.secondary)
                            Text("\(count)")
                                .font(.caption)
                        }
                    }
                }
            }

            Divider()

            // Import button
            Button {
                Task { await performCSVImport() }
            } label: {
                Text("Import & Enrich")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(preview.isEmpty && preview.duplicatesCount == 0)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var csvProgressCard: some View {
        VStack(spacing: 12) {
            ProgressView(value: csvImportService.importProgress)
                .tint(.blue)

            Text(csvImportService.currentPhase.description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func csvResultCard(_ result: CSVImportResult) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)

            Text("Import Complete!")
                .font(.headline)

            Text(result.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let range = result.dateRange {
                Text(formatDateRange(range))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Import More") {
                resetCSVState()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func errorCard(message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var howToExportSection: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("1. Log in to TrainingPeaks")
                Text("2. Go to Calendar view")
                Text("3. Click the gear icon (Settings)")
                Text("4. Select 'Export Workouts'")
                Text("5. Choose date range and export as CSV")
                Text("6. Save the file and select it here")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
        } label: {
            HStack {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.blue)
                Text("How to export from TrainingPeaks")
                    .font(.subheadline)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Actions

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        csvError = nil
        csvImportResult = nil

        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                csvError = "No file selected"
                return
            }

            Task {
                do {
                    parsedWorkouts = try await csvImportService.parseCSV(from: url)

                    let descriptor = FetchDescriptor<WorkoutRecord>()
                    let existingWorkouts = (try? modelContext.fetch(descriptor)) ?? []
                    csvPreview = csvImportService.previewImport(parsedWorkouts, existingWorkouts: existingWorkouts)

                    print("[CSVImport] Parsed \(parsedWorkouts.count) workouts, \(csvPreview?.newWorkoutsCount ?? 0) new")
                } catch {
                    csvError = error.localizedDescription
                    print("[CSVImport] Parse error: \(error)")
                }
            }

        case .failure(let error):
            csvError = error.localizedDescription
        }
    }

    private func performCSVImport() async {
        guard !parsedWorkouts.isEmpty else { return }

        csvError = nil
        csvImportResult = nil

        do {
            // Use enrichment import: matches TP workouts to existing Strava workouts
            let result = try await csvImportService.enrichImport(parsedWorkouts, into: modelContext)
            csvImportResult = result

            // Recalculate PMC after enrichment
            if (result.importedCount > 0 || result.enrichedCount > 0), let dateRange = result.dateRange {
                await recalculatePMCAfterImport(from: dateRange.lowerBound)
            }

            print("[CSVImport] Enrichment complete: \(result.summary)")
        } catch {
            csvError = error.localizedDescription
            print("[CSVImport] Import error: \(error)")
        }
    }

    private func recalculatePMCAfterImport(from startDate: Date) async {
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startDate >= startDate },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )

        guard let workouts = try? modelContext.fetch(descriptor), !workouts.isEmpty else { return }

        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())

        var previousCTL: Double = 0
        var previousATL: Double = 0

        if let dayBefore = calendar.date(byAdding: .day, value: -1, to: currentDate) {
            let metricsPredicate = #Predicate<DailyMetrics> { metrics in
                metrics.date >= dayBefore && metrics.date < currentDate
            }
            let metricsDescriptor = FetchDescriptor<DailyMetrics>(predicate: metricsPredicate)
            if let previousMetrics = try? modelContext.fetch(metricsDescriptor).first {
                previousCTL = previousMetrics.ctl
                previousATL = previousMetrics.atl
            }
        }

        while currentDate <= today {
            let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!

            let dayWorkouts = workouts.filter { workout in
                workout.startDate >= currentDate && workout.startDate < nextDate
            }
            let dailyTSS = dayWorkouts.reduce(0) { $0 + $1.tss }

            let newCTL = PMCCalculator.calculateCTL(previousCTL: previousCTL, todayTSS: dailyTSS)
            let newATL = PMCCalculator.calculateATL(previousATL: previousATL, todayTSS: dailyTSS)
            let newTSB = newCTL - newATL

            let metricsPredicate = #Predicate<DailyMetrics> { metrics in
                metrics.date >= currentDate && metrics.date < nextDate
            }
            let metricsDescriptor = FetchDescriptor<DailyMetrics>(predicate: metricsPredicate)
            let existingMetrics = try? modelContext.fetch(metricsDescriptor)

            if let metrics = existingMetrics?.first {
                metrics.totalTSS = dailyTSS
                metrics.ctl = newCTL
                metrics.atl = newATL
                metrics.tsb = newTSB
            } else {
                let metrics = DailyMetrics(
                    date: currentDate,
                    totalTSS: dailyTSS,
                    ctl: newCTL,
                    atl: newATL,
                    tsb: newTSB,
                    source: .calculated
                )
                modelContext.insert(metrics)
            }

            previousCTL = newCTL
            previousATL = newATL
            currentDate = nextDate
        }

        try? modelContext.save()
    }

    private func resetCSVState() {
        parsedWorkouts = []
        csvPreview = nil
        csvImportResult = nil
        csvError = nil
        csvImportService = TPCSVImportService()
    }

    private func formatDateRange(_ range: ClosedRange<Date>) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: range.lowerBound)) - \(formatter.string(from: range.upperBound))"
    }
}

// MARK: - Preview

#Preview {
    TPWorkoutImportView()
        .modelContainer(for: [WorkoutRecord.self, DailyMetrics.self], inMemory: true)
}
