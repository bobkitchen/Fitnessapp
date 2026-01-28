import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// View for importing workouts from TrainingPeaks (CSV bulk import or URL direct import)
struct TPWorkoutImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthKitService.self) private var healthKitService

    // Route enrichment state
    @State private var isEnrichingRoutes = false
    @State private var routeEnrichmentResult: RouteEnrichmentResult?

    // Tab selection
    @State private var selectedTab: ImportTab = .csvImport

    // CSV Import state
    @State private var showingFilePicker = false
    @State private var csvImportService = TPCSVImportService()
    @State private var parsedWorkouts: [TPWorkoutImport] = []
    @State private var csvPreview: CSVImportPreview?
    @State private var csvImportResult: CSVImportResult?
    @State private var csvError: String?

    // URL Import state
    @State private var urlText = ""
    @State private var importState: ImportState = .idle
    @State private var tpWorkoutData: TPWorkoutData?
    @State private var errorMessage: String?
    @State private var importedWorkout: WorkoutRecord?

    // PMC manual entry fields
    @State private var ctlText = ""
    @State private var atlText = ""
    @State private var tsbText = ""
    @State private var showPMCEntry = false

    // Shared workout data (from Share Extension)
    var prefilledURL: String?

    private let scraper = TrainingPeaksScraper()

    enum ImportTab: String, CaseIterable {
        case csvImport = "CSV Import"
        case urlImport = "URL Import"

        var icon: String {
            switch self {
            case .csvImport: return "doc.text"
            case .urlImport: return "link"
            }
        }
    }

    enum ImportState: Equatable {
        case idle
        case fetching
        case preview
        case importing
        case success
        case error
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab selector
                Picker("Import Type", selection: $selectedTab) {
                    ForEach(ImportTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                // Content based on selected tab
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        switch selectedTab {
                        case .csvImport:
                            csvImportSection
                        case .urlImport:
                            urlImportSection
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Import TrainingPeaks")
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
            .sheet(item: $importedWorkout) { workout in
                WorkoutDetailView(workout: workout)
                    .onDisappear {
                        dismiss()
                    }
            }
            .task {
                if let url = prefilledURL, !url.isEmpty {
                    selectedTab = .urlImport
                    urlText = url
                    await importWorkout()
                }
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

                Text("Import Workout History")
                    .font(.headline)

                Text("Export your workouts from TrainingPeaks as CSV and import them here to get accurate TSS, IF, and zone data.")
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
                StatItem(label: "New", value: "\(preview.newWorkoutsCount)")
                StatItem(label: "Duplicates", value: "\(preview.duplicatesCount)")
                StatItem(label: "Total TSS", value: String(format: "%.0f", preview.totalTSS))
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
                                .foregroundStyle(category.themeColor)
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
                Text("Import \(preview.newWorkoutsCount) Workouts")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(preview.isEmpty)
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

            // Show workout count during importing phase
            if csvImportService.currentPhase == .importing, let preview = csvPreview {
                let currentCount = Int(csvImportService.importProgress * Double(preview.newWorkoutsCount))
                Text("\(currentCount) of \(preview.newWorkoutsCount) workouts")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
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

            // Route enrichment status
            if isEnrichingRoutes {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching GPS routes...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let routeResult = routeEnrichmentResult, routeResult.enrichedCount > 0 {
                Label("\(routeResult.enrichedCount) route maps added", systemImage: "map.fill")
                    .font(.caption)
                    .foregroundStyle(.blue)
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

    // MARK: - URL Import Section

    @ViewBuilder
    private var urlImportSection: some View {
        VStack(spacing: Spacing.lg) {
            switch importState {
            case .idle, .fetching, .error:
                urlInputCard
            case .preview, .importing:
                workoutPreviewCard
            case .success:
                urlSuccessCard
            }
        }
        .animation(AppAnimation.springSmooth, value: importState)
    }

    // MARK: - URL Input Card

    @ViewBuilder
    private var urlInputCard: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Import TrainingPeaks Workout")
                .sectionHeaderStyle()

            VStack(spacing: Spacing.md) {
                Text("Paste a shared TrainingPeaks workout URL to import it directly into your training log.")
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(Color.textSecondary)

                HStack(spacing: Spacing.xs) {
                    TextField("https://trainingpeaks.com/...", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .disabled(importState == .fetching)

                    if !urlText.isEmpty {
                        Button {
                            urlText = ""
                            resetState()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Color.textSecondary)
                        }
                    }
                }

                if importState == .fetching {
                    HStack(spacing: Spacing.xs) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Fetching workout data...")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(Color.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                if importState == .error, let error = errorMessage {
                    HStack(spacing: Spacing.xs) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Color.statusLow)
                        Text(error)
                            .font(AppFont.bodySmall)
                            .foregroundStyle(Color.statusLow)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task { await importWorkout() }
                } label: {
                    HStack {
                        if importState == .fetching {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(importState == .fetching ? "Fetching..." : "Import Workout")
                            .font(AppFont.bodyMedium)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentPrimary)
                .disabled(urlText.isEmpty || importState == .fetching)
            }
            .padding(Spacing.md)
            .cardBackground(cornerRadius: CornerRadius.large)
        }
        .animatedAppearance(index: 0)
    }

    // MARK: - Workout Preview Card

    @ViewBuilder
    private var workoutPreviewCard: some View {
        if let tpData = tpWorkoutData {
            VStack(alignment: .leading, spacing: Spacing.md) {
                // Activity header
                HStack(spacing: Spacing.xs) {
                    Image(systemName: tpData.activityCategory.icon)
                        .font(.title3)
                        .foregroundStyle(tpData.activityCategory.themeColor)
                    Text(tpData.title ?? tpData.activityType)
                        .font(AppFont.titleMedium)
                        .foregroundStyle(Color.textPrimary)
                }

                // Date + duration
                HStack(spacing: Spacing.xs) {
                    Text(tpData.startDate, style: .date)
                    Text("\u{00B7}")
                    Text(formatDuration(tpData.duration))
                }
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)

                // Metric row
                HStack(spacing: Spacing.lg) {
                    URLMetricItem(label: "TSS", value: "\(Int(tpData.tss))")
                    URLMetricItem(
                        label: "IF",
                        value: tpData.intensityFactor.map { String(format: "%.2f", $0) } ?? "--"
                    )
                    URLMetricItem(label: "Distance", value: formatDistance(tpData.distance))
                }
                .padding(.vertical, Spacing.sm)

                // PMC entry (collapsed disclosure)
                DisclosureGroup("PMC Values (Optional)", isExpanded: $showPMCEntry) {
                    pmcEntryContent
                }
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .tint(Color.accentPrimary)

                // Import button
                Button {
                    Task { await confirmImport() }
                } label: {
                    HStack {
                        if importState == .importing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        }
                        Text(importState == .importing ? "Importing..." : "Import Workout")
                            .font(AppFont.bodyMedium)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentPrimary)
                .disabled(importState == .importing || (hasPMCValues && parsedPMCValues == nil))
            }
            .padding(Spacing.md)
            .cardBackground(cornerRadius: CornerRadius.large)
            .animatedAppearance(index: 0)
        }
    }

    // MARK: - URL Success Card

    @ViewBuilder
    private var urlSuccessCard: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(Color.statusOptimal)

            Text("Workout Imported!")
                .font(AppFont.titleMedium)
                .foregroundStyle(Color.textPrimary)

            Text("Added to your training log")
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)

            Button("Import Another") {
                urlText = ""
                resetState()
            }
            .buttonStyle(.bordered)
            .tint(Color.accentPrimary)
        }
        .padding(Spacing.md)
        .cardBackground(cornerRadius: CornerRadius.large)
        .animatedAppearance(index: 0)
    }

    // MARK: - URL Metric Item

    private struct URLMetricItem: View {
        let label: String
        let value: String

        var body: some View {
            VStack(spacing: Spacing.xxs) {
                Text(value)
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Color.textPrimary)
                Text(label)
                    .font(AppFont.labelMedium)
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - PMC Entry

    private var hasPMCValues: Bool {
        !ctlText.isEmpty || !atlText.isEmpty || !tsbText.isEmpty
    }

    private var parsedPMCValues: (ctl: Double, atl: Double, tsb: Double)? {
        guard let ctl = Double(ctlText),
              let atl = Double(atlText),
              let tsb = Double(tsbText),
              ctl >= 0 && ctl <= 200,
              atl >= 0 && atl <= 300,
              tsb >= -100 && tsb <= 100
        else { return nil }
        return (ctl, atl, tsb)
    }

    @ViewBuilder
    private var pmcEntryContent: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Enter your current PMC values from TrainingPeaks to calibrate fitness tracking")
                .font(AppFont.bodySmall)
                .foregroundStyle(Color.textSecondary)
                .padding(.top, Spacing.xs)

            HStack(spacing: Spacing.md) {
                pmcField(label: "CTL", hint: "Fitness", text: $ctlText)
                pmcField(label: "ATL", hint: "Fatigue", text: $atlText)
                pmcField(label: "TSB", hint: "Form", text: $tsbText)
            }

            if hasPMCValues && parsedPMCValues == nil {
                Text("Enter valid numbers (CTL: 0-200, ATL: 0-300, TSB: -100 to 100)")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Color.statusLow)
            }
        }
    }

    @ViewBuilder
    private func pmcField(label: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(label)
                .font(AppFont.labelMedium)
                .foregroundStyle(Color.textSecondary)
            TextField(hint, text: text)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
        }
    }

    // MARK: - Shared Card Components

    @ViewBuilder
    private func errorCard(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Error")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Try Again") {
                resetState()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helper Views

    struct StatItem: View {
        let label: String
        let value: String

        var body: some View {
            VStack(spacing: 2) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - URL Import Actions

    private func importWorkout() async {
        guard !urlText.isEmpty else { return }

        resetState()
        importState = .fetching

        do {
            let tpData = try await scraper.fetchWorkout(from: urlText)
            tpWorkoutData = tpData

            print("[TPImport] Parsed TP workout: \(tpData.activityType), TSS=\(tpData.tss), duration=\(tpData.duration)s, date=\(tpData.startDate)")

            if checkForDuplicate(tpData: tpData) {
                errorMessage = "This workout appears to already be imported"
                importState = .error
                return
            }

            importState = .preview
        } catch {
            errorMessage = error.localizedDescription
            importState = .error
            print("[TPImport] Error: \(error)")
        }
    }

    private func confirmImport() async {
        guard let tpData = tpWorkoutData else { return }

        importState = .importing

        do {
            let record = createWorkoutRecord(from: tpData)
            modelContext.insert(record)

            if let pmcValues = parsedPMCValues {
                let learningEngine = TSSLearningEngine(modelContext: modelContext)
                try await learningEngine.recordCombinedCalibration(
                    workout: record,
                    trainingPeaksTSS: tpData.tss,
                    trainingPeaksIF: tpData.intensityFactor,
                    pmcValues: pmcValues,
                    matchConfidence: 1.0
                )
            }

            try modelContext.save()

            await recalculatePMCAfterImport(from: tpData.startDate)

            importedWorkout = record
        } catch {
            errorMessage = error.localizedDescription
            importState = .error
        }
    }

    private func createWorkoutRecord(from tpData: TPWorkoutData) -> WorkoutRecord {
        // Use scraped IF, or compute from TSS and duration: IF = sqrt(TSS / (hours * 100))
        let intensityFactor: Double
        if let scrapedIF = tpData.intensityFactor, scrapedIF > 0 {
            intensityFactor = scrapedIF
        } else if tpData.tss > 0 && tpData.duration > 0 {
            let hours = tpData.duration / 3600.0
            intensityFactor = sqrt(tpData.tss / (hours * 100.0))
        } else {
            intensityFactor = 0
        }

        let record = WorkoutRecord(
            healthKitUUID: nil,
            activityType: tpData.activityType,
            activityCategory: tpData.activityCategory,
            title: tpData.title,
            startDate: tpData.startDate,
            endDate: tpData.startDate.addingTimeInterval(tpData.duration),
            durationSeconds: tpData.duration,
            distanceMeters: tpData.distance,
            tss: tpData.tss,
            tssType: .trainingPeaks,
            intensityFactor: intensityFactor
        )
        record.source = .trainingPeaks
        record.averageHeartRate = tpData.averageHR
        record.averagePower = tpData.averagePower
        record.averagePaceSecondsPerKm = tpData.averagePace
        if let coords = tpData.routeCoordinates, !coords.isEmpty {
            record.hasRoute = true
            record.routeData = WorkoutRecord.encodeRoute(coords)
        }
        return record
    }

    private func checkForDuplicate(tpData: TPWorkoutData) -> Bool {
        let oneHourBefore = tpData.startDate.addingTimeInterval(-3600)
        let oneHourAfter = tpData.startDate.addingTimeInterval(3600)
        let category = tpData.activityCategory.rawValue

        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate {
                $0.startDate >= oneHourBefore &&
                $0.startDate <= oneHourAfter &&
                $0.activityCategoryRaw == category
            }
        )

        guard let matches = try? modelContext.fetch(descriptor) else { return false }

        for match in matches {
            let durationRatio = match.durationSeconds / tpData.duration
            if durationRatio >= 0.8 && durationRatio <= 1.2 {
                return true
            }
        }
        return false
    }

    private func resetState() {
        importState = .idle
        tpWorkoutData = nil
        errorMessage = nil
        ctlText = ""
        atlText = ""
        tsbText = ""
        showPMCEntry = false
    }

    // MARK: - Formatting Helpers

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hrs = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    private func formatDistance(_ meters: Double?) -> String {
        guard let meters = meters, meters > 0 else { return "--" }
        return String(format: "%.1f km", meters / 1000.0)
    }

    // MARK: - CSV Import Actions

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

                    // Fetch existing workouts for preview
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
            let result = try await csvImportService.importWorkouts(parsedWorkouts, into: modelContext)
            csvImportResult = result

            // Recalculate PMC after import
            if result.importedCount > 0, let dateRange = result.dateRange {
                await recalculatePMCAfterImport(from: dateRange.lowerBound)

                // Enrich routes from HealthKit
                isEnrichingRoutes = true
                let enrichService = RouteEnrichmentService(healthKitService: healthKitService)
                routeEnrichmentResult = await enrichService.enrichRoutes(
                    modelContext: modelContext, dateRange: dateRange
                )
                isEnrichingRoutes = false
            }

            print("[CSVImport] Import complete: \(result.summary)")
        } catch {
            csvError = error.localizedDescription
            print("[CSVImport] Import error: \(error)")
        }
    }

    private func recalculatePMCAfterImport(from startDate: Date) async {
        // Fetch all workouts from start date
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startDate >= startDate },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )

        guard let workouts = try? modelContext.fetch(descriptor), !workouts.isEmpty else { return }

        // Group by day and recalculate PMC
        let calendar = Calendar.current
        var currentDate = calendar.startOfDay(for: startDate)
        let today = calendar.startOfDay(for: Date())

        // Get previous day's metrics for seed values
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

        // Process each day
        while currentDate <= today {
            let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!

            // Get workouts for this day
            let dayWorkouts = workouts.filter { workout in
                workout.startDate >= currentDate && workout.startDate < nextDate
            }
            let dailyTSS = dayWorkouts.reduce(0) { $0 + $1.tss }

            // Calculate new CTL and ATL
            let newCTL = PMCCalculator.calculateCTL(previousCTL: previousCTL, todayTSS: dailyTSS)
            let newATL = PMCCalculator.calculateATL(previousATL: previousATL, todayTSS: dailyTSS)
            let newTSB = newCTL - newATL

            // Get or create DailyMetrics for this day
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
        routeEnrichmentResult = nil
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
        .modelContainer(for: [WorkoutRecord.self, TSSScalingProfile.self, TSSCalibrationDataPoint.self], inMemory: true)
}
