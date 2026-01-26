import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// View for importing workouts from TrainingPeaks (CSV bulk import or URL calibration)
struct TPWorkoutImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Tab selection
    @State private var selectedTab: ImportTab = .csvImport

    // CSV Import state
    @State private var showingFilePicker = false
    @State private var csvImportService = TPCSVImportService()
    @State private var parsedWorkouts: [TPWorkoutImport] = []
    @State private var csvPreview: CSVImportPreview?
    @State private var csvImportResult: CSVImportResult?
    @State private var csvError: String?

    // URL Import state (calibration)
    @State private var urlText = ""
    @State private var importState: ImportState = .idle
    @State private var tpWorkoutData: TPWorkoutData?
    @State private var matchResult: WorkoutMatchResult?
    @State private var allMatches: [WorkoutMatchResult] = []
    @State private var selectedWorkout: WorkoutRecord?
    @State private var errorMessage: String?
    @State private var showingCompletionAlert = false
    @State private var importStats: URLImportStatistics?

    // PMC manual entry fields
    @State private var ctlText = ""
    @State private var atlText = ""
    @State private var tsbText = ""
    @State private var showPMCEntry = true  // Expanded by default so users see the option

    // Shared workout data (from Share Extension)
    var prefilledURL: String?

    private let scraper = TrainingPeaksScraper()

    enum ImportTab: String, CaseIterable {
        case csvImport = "CSV Import"
        case urlCalibration = "URL Calibration"

        var icon: String {
            switch self {
            case .csvImport: return "doc.text"
            case .urlCalibration: return "link"
            }
        }
    }

    enum ImportState {
        case idle
        case fetching
        case matching
        case matched
        case noMatch
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
                    VStack(spacing: 24) {
                        switch selectedTab {
                        case .csvImport:
                            csvImportSection
                        case .urlCalibration:
                            urlCalibrationSection
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
            .alert("Calibration Complete", isPresented: $showingCompletionAlert) {
                Button("Keep Importing") { }
                Button("Disable Import") {
                    disableURLImport()
                }
            } message: {
                Text("Your TSS calculations are now well-calibrated with TrainingPeaks. You can continue importing more workouts or disable this feature.")
            }
            .task {
                await loadStats()
                // If we have a prefilled URL from Share Extension, auto-import
                if let url = prefilledURL, !url.isEmpty {
                    selectedTab = .urlCalibration
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

    // MARK: - URL Calibration Section

    @ViewBuilder
    private var urlCalibrationSection: some View {
        VStack(spacing: 24) {
            // Header / Instructions
            headerSection

            // URL Input
            urlInputSection

            // Status / Results
            statusSection

            // Calibration Progress
            if let stats = importStats {
                calibrationProgressSection(stats)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 44))
                .foregroundStyle(.blue)

            Text("Calibrate TSS with TrainingPeaks")
                .font(.headline)

            Text("Paste a shared TrainingPeaks workout URL to compare TSS values and train the learning model.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TrainingPeaks Workout URL")
                .font(.subheadline)
                .fontWeight(.medium)

            HStack {
                TextField("https://trainingpeaks.com/...", text: $urlText)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .disabled(importState == .fetching || importState == .importing)

                if !urlText.isEmpty {
                    Button {
                        urlText = ""
                        resetState()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                Task { await importWorkout() }
            } label: {
                HStack {
                    if importState == .fetching || importState == .matching || importState == .importing {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(buttonLabel)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(urlText.isEmpty || importState == .fetching || importState == .importing)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusSection: some View {
        switch importState {
        case .idle:
            EmptyView()

        case .fetching:
            statusCard(
                icon: "arrow.down.circle",
                iconColor: .blue,
                title: "Fetching workout...",
                subtitle: "Parsing TrainingPeaks page"
            )

        case .matching:
            statusCard(
                icon: "magnifyingglass",
                iconColor: .blue,
                title: "Finding match...",
                subtitle: "Searching for matching HealthKit workout"
            )

        case .matched:
            if let tpData = tpWorkoutData, let match = matchResult {
                matchedWorkoutCard(tpData: tpData, match: match)
            }

        case .noMatch:
            if let tpData = tpWorkoutData {
                noMatchCard(tpData: tpData)
            }

        case .importing:
            statusCard(
                icon: "arrow.triangle.2.circlepath",
                iconColor: .blue,
                title: "Importing...",
                subtitle: "Recording calibration data"
            )

        case .success:
            successCard

        case .error:
            if let error = errorMessage {
                errorCard(message: error)
            }
        }
    }

    @ViewBuilder
    private func calibrationProgressSection(_ stats: URLImportStatistics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Calibration Progress")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(stats.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(stats.isCalibrationComplete ? Color.green : Color.blue)
                        .frame(width: geometry.size.width * min(1.0, stats.progressToMinimum), height: 8)
                }
            }
            .frame(height: 8)

            // Stats grid
            HStack(spacing: 16) {
                StatItem(label: "Samples", value: "\(stats.totalSamples)/\(URLImportStatistics.minimumSamples)")
                StatItem(label: "Confidence", value: String(format: "%.0f%%", stats.confidence * 100))
                StatItem(label: "Scaling", value: stats.scalingDescription)
            }

            // Per-sport breakdown
            if !stats.perSportCounts.isEmpty {
                HStack(spacing: 12) {
                    ForEach(Array(stats.perSportCounts.sorted { $0.value > $1.value }), id: \.key) { category, count in
                        HStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .foregroundStyle(category.themeColor)
                            Text("\(count)")
                                .font(.caption)
                        }
                    }
                }
            }

            // Completion suggestion
            if stats.canDisableImport && !stats.isCalibrationComplete {
                Button {
                    showingCompletionAlert = true
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Calibration ready - tap to complete")
                            .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Card Components

    @ViewBuilder
    private func statusCard(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func matchedWorkoutCard(tpData: TPWorkoutData, match: WorkoutMatchResult) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Match Found")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(match.qualityDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Comparison
            HStack(spacing: 0) {
                // TrainingPeaks side
                VStack(alignment: .leading, spacing: 8) {
                    Text("TrainingPeaks")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Image(systemName: tpData.activityCategory.icon)
                            .foregroundStyle(tpData.activityCategory.themeColor)
                        Text(tpData.activityType)
                            .font(.subheadline)
                    }

                    Text("TSS: \(Int(tpData.tss))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.orange)

                    if let ifValue = tpData.intensityFactor {
                        Text("IF: \(String(format: "%.2f", ifValue))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Arrow
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)

                // HealthKit side
                VStack(alignment: .trailing, spacing: 8) {
                    Text("This App")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text(match.workout.activityCategory.rawValue)
                            .font(.subheadline)
                        Image(systemName: match.workout.activityCategory.icon)
                            .foregroundStyle(match.workout.activityCategory.themeColor)
                    }

                    Text("TSS: \(Int(match.workout.tss))")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)

                    Text("IF: \(String(format: "%.2f", match.workout.intensityFactor))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Difference
            let tssDiff = tpData.tss - match.workout.tss
            let tssPercent = (tpData.tss / max(1, match.workout.tss) - 1) * 100

            HStack {
                Spacer()
                Text("Difference: \(tssDiff >= 0 ? "+" : "")\(Int(tssDiff)) (\(tssPercent >= 0 ? "+" : "")\(String(format: "%.0f%%", tssPercent)))")
                    .font(.caption)
                    .foregroundStyle(abs(tssPercent) < 10 ? .green : .orange)
                Spacer()
            }

            Divider()

            // PMC Entry Section
            pmcEntrySection

            Divider()

            // Actions
            Button {
                Task { await confirmImport() }
            } label: {
                Text(hasPMCValues ? "Apply Calibration (TSS + PMC)" : "Import TSS Calibration")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            // Show other matches if available
            if allMatches.count > 1 {
                DisclosureGroup("Other potential matches (\(allMatches.count - 1))") {
                    ForEach(allMatches.dropFirst().prefix(3), id: \.workout.id) { altMatch in
                        alternateMatchRow(altMatch)
                    }
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - PMC Entry Section

    /// Whether user has entered any PMC values
    private var hasPMCValues: Bool {
        !ctlText.isEmpty || !atlText.isEmpty || !tsbText.isEmpty
    }

    /// Parsed PMC values (nil if invalid)
    private var parsedPMCValues: (ctl: Double, atl: Double, tsb: Double)? {
        guard let ctl = Double(ctlText),
              let atl = Double(atlText),
              let tsb = Double(tsbText),
              ctl >= 0 && ctl <= 200,   // Reasonable CTL range
              atl >= 0 && atl <= 300,   // Reasonable ATL range
              tsb >= -100 && tsb <= 100 // Reasonable TSB range
        else { return nil }
        return (ctl, atl, tsb)
    }

    @ViewBuilder
    private var pmcEntrySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(.blue)
                Text("PMC Values (Optional)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Button {
                    withAnimation {
                        showPMCEntry.toggle()
                    }
                } label: {
                    Image(systemName: showPMCEntry ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if showPMCEntry {
                Text("Enter your current PMC values from TrainingPeaks to calibrate fitness tracking")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    pmcField(label: "CTL", hint: "Fitness", text: $ctlText)
                    pmcField(label: "ATL", hint: "Fatigue", text: $atlText)
                    pmcField(label: "TSB", hint: "Form", text: $tsbText)
                }

                if hasPMCValues && parsedPMCValues == nil {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Enter valid numbers (CTL: 0-200, ATL: 0-300, TSB: -100 to 100)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if let pmc = parsedPMCValues {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("PMC: CTL \(Int(pmc.ctl)) / ATL \(Int(pmc.atl)) / TSB \(Int(pmc.tsb))")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func pmcField(label: String, hint: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.medium)
            TextField(hint, text: text)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
        }
    }

    @ViewBuilder
    private func alternateMatchRow(_ match: WorkoutMatchResult) -> some View {
        Button {
            selectAlternateMatch(match)
        } label: {
            HStack {
                Image(systemName: match.workout.activityCategory.icon)
                    .foregroundStyle(match.workout.activityCategory.themeColor)

                VStack(alignment: .leading) {
                    Text(match.workout.dateFormatted)
                        .font(.caption)
                    Text("TSS: \(Int(match.workout.tss))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(String(format: "%.0f%%", match.confidenceScore * 100)) match")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func noMatchCard(tpData: TPWorkoutData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .foregroundStyle(.orange)
                Text("No Match Found")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            Text("Could not find a matching workout in your HealthKit data.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("TrainingPeaks workout:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Image(systemName: tpData.activityCategory.icon)
                        .foregroundStyle(tpData.activityCategory.themeColor)
                    Text("\(tpData.activityType) - TSS: \(Int(tpData.tss))")
                }
                HStack {
                    Text(tpData.startDate, style: .date)
                    Text("•")
                    Text(formatDuration(tpData.duration))
                    if let dist = tpData.distance {
                        Text("•")
                        Text("\(Int(dist))m")
                    }
                }
                .font(.caption)
            }

            // Show available workouts for context
            if !allMatches.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Possible matches found but below threshold:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(allMatches.prefix(3), id: \.workout.id) { match in
                        HStack {
                            Image(systemName: match.workout.activityCategory.icon)
                                .foregroundStyle(match.workout.activityCategory.themeColor)
                                .frame(width: 20)
                            Text(match.workout.dateFormatted)
                            Text(match.workout.durationFormatted)
                            Spacer()
                            Text("\(Int(match.confidenceScore * 100))%")
                                .foregroundStyle(.orange)
                        }
                        .font(.caption)
                    }
                }
            }

            Text("Ensure the workout exists in Apple Health with the same date and similar duration.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    /// Format duration in seconds to readable format
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hrs = Int(seconds) / 3600
        let mins = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        if hrs > 0 {
            return String(format: "%d:%02d:%02d", hrs, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }

    @ViewBuilder
    private var successCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)

            Text("Calibration Recorded!")
                .font(.headline)

            Text("The TSS comparison has been saved and will improve future calculations.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Import Another") {
                resetState()
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

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

    // MARK: - Computed Properties

    private var buttonLabel: String {
        switch importState {
        case .fetching: return "Fetching..."
        case .matching: return "Matching..."
        case .importing: return "Importing..."
        default: return "Import Workout"
        }
    }

    // MARK: - Actions

    private func importWorkout() async {
        guard !urlText.isEmpty else { return }

        resetState()
        importState = .fetching
        errorMessage = nil

        do {
            // Fetch and parse the TP workout
            let tpData = try await scraper.fetchWorkout(from: urlText)
            tpWorkoutData = tpData

            print("[TPImport] Parsed TP workout: \(tpData.activityType), TSS=\(tpData.tss), duration=\(tpData.duration)s, date=\(tpData.startDate)")

            importState = .matching

            // Find matching HealthKit workout with wider search window
            let matchingService = WorkoutMatchingService(modelContext: modelContext)
            allMatches = try matchingService.findAllMatches(for: tpData, searchWindow: 3)

            print("[TPImport] Found \(allMatches.count) potential matches")

            if let bestMatch = allMatches.first {
                print("[TPImport] Best match: \(bestMatch.workout.activityCategory.rawValue) on \(bestMatch.workout.dateFormatted), confidence=\(bestMatch.confidenceScore)")

                // Accept matches with at least 40% confidence
                if bestMatch.confidenceScore >= 0.40 {
                    matchResult = bestMatch
                    selectedWorkout = bestMatch.workout
                    importState = .matched
                } else {
                    // Low confidence - show as no match but keep in allMatches for display
                    importState = .noMatch
                }
            } else {
                importState = .noMatch
            }
        } catch {
            errorMessage = error.localizedDescription
            importState = .error
            print("[TPImport] Error: \(error)")
        }
    }

    private func confirmImport() async {
        guard let tpData = tpWorkoutData,
              let workout = selectedWorkout,
              let match = matchResult else { return }

        importState = .importing

        do {
            let learningEngine = TSSLearningEngine(modelContext: modelContext)

            // Use combined calibration if PMC values are provided
            if let pmcValues = parsedPMCValues {
                try await learningEngine.recordCombinedCalibration(
                    workout: workout,
                    trainingPeaksTSS: tpData.tss,
                    trainingPeaksIF: tpData.intensityFactor,
                    pmcValues: pmcValues,
                    matchConfidence: match.confidenceScore
                )
            } else {
                // TSS-only calibration
                try await learningEngine.recordDirectTSSComparison(
                    workout: workout,
                    trainingPeaksTSS: tpData.tss,
                    trainingPeaksIF: tpData.intensityFactor,
                    matchConfidence: match.confidenceScore
                )
            }

            importState = .success
            await loadStats()

            // Check if we should suggest completion
            if let stats = importStats, stats.canDisableImport {
                showingCompletionAlert = true
            }
        } catch {
            errorMessage = error.localizedDescription
            importState = .error
        }
    }

    private func selectAlternateMatch(_ match: WorkoutMatchResult) {
        matchResult = match
        selectedWorkout = match.workout
    }

    private func resetState() {
        importState = .idle
        tpWorkoutData = nil
        matchResult = nil
        allMatches = []
        selectedWorkout = nil
        errorMessage = nil
        ctlText = ""
        atlText = ""
        tsbText = ""
        showPMCEntry = false
    }

    private func loadStats() async {
        do {
            let learningEngine = TSSLearningEngine(modelContext: modelContext)
            importStats = try learningEngine.getURLImportStatistics()
        } catch {
            print("[TPImport] Failed to load stats: \(error)")
        }
    }

    private func disableURLImport() {
        do {
            let learningEngine = TSSLearningEngine(modelContext: modelContext)
            let profile = try learningEngine.getOrCreateScalingProfile()
            profile.tssCalibrationComplete = true
            profile.urlImportEnabled = false
            try modelContext.save()
            dismiss()
        } catch {
            print("[TPImport] Failed to disable import: \(error)")
        }
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
