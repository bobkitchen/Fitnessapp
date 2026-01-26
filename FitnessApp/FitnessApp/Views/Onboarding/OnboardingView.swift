import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers

/// 3-page onboarding flow: Welcome + HealthKit -> TrainingPeaks Import -> Setup Complete
/// Note: HealthKit sync now only imports wellness data. Workouts come from TrainingPeaks CSV.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService

    @State private var currentPage = 0
    @State private var isRequestingHealthKit = false
    @State private var isSyncing = false
    @State private var syncStarted = false
    @State private var syncProgress: SyncProgress = SyncProgress()
    @State private var detectedThresholds: DetectedThresholds?
    @State private var syncError: String?

    // TrainingPeaks import state
    @State private var showingFilePicker = false
    @State private var csvImportService = TPCSVImportService()
    @State private var tpImportResult: CSVImportResult?
    @State private var tpImportError: String?
    @State private var parsedWorkouts: [TPWorkoutImport] = []
    @State private var csvPreview: CSVImportPreview?
    @State private var isTransitioning = false

    var body: some View {
        TabView(selection: $currentPage) {
            // Page 1: Welcome + HealthKit (wellness data only)
            WelcomeHealthKitPage(
                isRequesting: $isRequestingHealthKit,
                isAuthorized: healthKitService.isAuthorized,
                hasAttemptedAuth: healthKitService.hasAttemptedAuthorization,
                authError: healthKitService.authorizationError,
                onRequestAccess: requestHealthKitAccess,
                onOpenSettings: { healthKitService.openHealthAppSettings() }
            )
            .tag(0)

            // Page 2: TrainingPeaks Import
            TrainingPeaksImportPage(
                showingFilePicker: $showingFilePicker,
                isImporting: csvImportService.isImporting,
                importResult: tpImportResult,
                importError: tpImportError,
                csvPreview: csvPreview,
                onSkip: { advanceToCompletion() },
                onContinue: { advanceToCompletion() },
                onConfirmImport: { await performCSVImport() }
            )
            .tag(1)
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
                allowsMultipleSelection: false
            ) { result in
                handleCSVFileSelection(result)
            }

            // Page 3: Sync Progress + Completion
            SyncProgressPage(
                isSyncing: isSyncing,
                isTransitioning: isTransitioning,
                progress: syncProgress,
                detectedThresholds: detectedThresholds,
                error: syncError,
                onComplete: completeOnboarding
            )
            .tag(2)
            .onAppear {
                // Auto-start sync when page appears
                if !syncStarted && !isSyncing {
                    syncStarted = true
                    startSync()
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .interactiveDismissDisabled()
        // Auto-advance to TrainingPeaks import page after HealthKit authorization
        .onChange(of: healthKitService.isAuthorized) { _, isAuthorized in
            if isAuthorized && currentPage == 0 {
                withAnimation {
                    currentPage = 1
                }
            }
        }
    }

    private func advanceToCompletion() {
        withAnimation {
            currentPage = 2
        }
    }

    private func requestHealthKitAccess() {
        isRequestingHealthKit = true
        Task { @MainActor in
            await healthKitService.requestAuthorization()
            isRequestingHealthKit = false
        }
    }

    private func handleCSVFileSelection(_ result: Result<[URL], Error>) {
        tpImportError = nil
        tpImportResult = nil
        csvPreview = nil
        parsedWorkouts = []

        switch result {
        case .success(let urls):
            guard let url = urls.first else {
                tpImportError = "No file selected"
                return
            }

            Task {
                do {
                    // Step 1: Parse CSV only (don't import yet)
                    parsedWorkouts = try await csvImportService.parseCSV(from: url)

                    // Step 2: Generate preview
                    let descriptor = FetchDescriptor<WorkoutRecord>()
                    let existingWorkouts = (try? modelContext.fetch(descriptor)) ?? []
                    csvPreview = csvImportService.previewImport(parsedWorkouts, existingWorkouts: existingWorkouts)
                    print("[Onboarding] CSV parsed: \(parsedWorkouts.count) workouts, preview shows \(csvPreview?.newWorkoutsCount ?? 0) new")
                } catch {
                    tpImportError = error.localizedDescription
                    print("[Onboarding] CSV parse error: \(error)")
                }
            }

        case .failure(let error):
            tpImportError = error.localizedDescription
        }
    }

    private func performCSVImport() async {
        guard !parsedWorkouts.isEmpty else { return }

        do {
            let result = try await csvImportService.importWorkouts(parsedWorkouts, into: modelContext)

            // Explicitly save and verify
            try modelContext.save()

            tpImportResult = result
            parsedWorkouts = []
            csvPreview = nil
            print("[Onboarding] TrainingPeaks import complete: \(result.summary)")
        } catch {
            tpImportError = error.localizedDescription
            print("[Onboarding] TrainingPeaks import error: \(error)")
        }
    }

    private func startSync() {
        isSyncing = true
        syncError = nil

        Task {
            do {
                // Create profile first if it doesn't exist
                let profileDescriptor = FetchDescriptor<AthleteProfile>()
                let existingProfiles = try modelContext.fetch(profileDescriptor)
                let profile: AthleteProfile
                if let existing = existingProfiles.first {
                    profile = existing
                } else {
                    profile = AthleteProfile()
                    modelContext.insert(profile)
                    try modelContext.save()
                }

                // Start sync (wellness data only - workouts came from TrainingPeaks import)
                let syncService = WorkoutSyncService(healthKitService: healthKitService)

                await syncService.performInitialSync(modelContext: modelContext, profile: profile)

                // Update progress from service
                syncProgress = syncService.syncProgress

                if let error = syncService.syncError {
                    syncError = error.localizedDescription
                }

                // Auto-detect thresholds from imported TrainingPeaks workouts
                detectedThresholds = await syncService.autoDetectThresholds(modelContext: modelContext)

                // Apply detected thresholds to profile
                if let detected = detectedThresholds {
                    if let ftp = detected.estimatedFTP {
                        profile.ftpWatts = ftp
                    }
                    if let runFtp = detected.estimatedRunningFTP {
                        profile.runningFTPWatts = runFtp
                    }
                    if let lthr = detected.estimatedLTHR {
                        profile.thresholdHeartRate = lthr
                    }
                    if let maxHr = detected.estimatedMaxHR {
                        profile.maxHeartRate = maxHr
                    }
                    if let pace = detected.estimatedThresholdPace {
                        profile.thresholdPaceSecondsPerKm = pace
                    }
                    try modelContext.save()
                }
            } catch {
                syncError = "Failed to save data: \(error.localizedDescription)"
                print("[Onboarding] Sync error: \(error)")
            }

            isSyncing = false
        }
    }

    private func completeOnboarding() {
        guard !isTransitioning else { return }
        isTransitioning = true

        Task {
            do {
                // Final save to ensure all data is persisted
                try modelContext.save()

                // Small delay to ensure disk write completes
                try await Task.sleep(for: .milliseconds(100))

                await MainActor.run {
                    UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
                    hasCompletedOnboarding = true
                }
            } catch {
                syncError = "Failed to save your data. Please try again."
                isTransitioning = false
            }
        }
    }
}

// MARK: - Page 1: Welcome + HealthKit

struct WelcomeHealthKitPage: View {
    @Binding var isRequesting: Bool
    let isAuthorized: Bool
    let hasAttemptedAuth: Bool
    let authError: Error?
    let onRequestAccess: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon and title
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentPrimary)

            Text("AI Fitness Coach")
                .font(AppFont.displaySmall)
                .foregroundStyle(Color.textPrimary)

            Text("Your intelligent training companion")
                .font(AppFont.bodyLarge)
                .foregroundStyle(Color.textSecondary)

            Spacer()

            // Features
            VStack(spacing: 12) {
                OnboardingFeatureRow(icon: "chart.line.uptrend.xyaxis", title: "Track Fitness", subtitle: "PMC with CTL, ATL, TSB")
                OnboardingFeatureRow(icon: "heart.fill", title: "Monitor Recovery", subtitle: "HRV, sleep, and wellness")
                OnboardingFeatureRow(icon: "sparkles", title: "AI Coaching", subtitle: "Personalized advice")
            }
            .padding(.horizontal, 32)

            Spacer()

            // Simulator warning
            if HealthKitService.isRunningOnSimulator {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("HealthKit requires a physical iPhone. The authorization dialog won't appear on the Simulator.")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 32)
            }

            // HealthKit connection
            VStack(spacing: 16) {
                if isAuthorized {
                    // Show connecting state - auto-advances to next page
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(.green)
                        Text("Connected! Loading...")
                            .foregroundStyle(.green)
                    }
                    .font(AppFont.labelLarge)
                } else {
                    // Main connect button
                    Button {
                        onRequestAccess()
                    } label: {
                        HStack(spacing: 8) {
                            if isRequesting {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Image(systemName: "heart.fill")
                            }
                            Text(hasAttemptedAuth ? "Try Again" : "Connect Apple Health")
                        }
                        .font(AppFont.labelLarge)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                    }
                    .disabled(isRequesting)
                    .padding(.horizontal, 32)

                    // Show error if there was one
                    if let error = authError {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error.localizedDescription)
                                .font(AppFont.captionSmall)
                                .foregroundStyle(Color.textSecondary)
                        }
                        .padding(.horizontal, 32)
                    }

                    // Instructional text
                    if hasAttemptedAuth && !isRequesting {
                        VStack(spacing: 12) {
                            Text("If the permission dialog didn't appear, you may need to enable access manually:")
                                .font(AppFont.captionSmall)
                                .foregroundStyle(Color.textTertiary)
                                .multilineTextAlignment(.center)

                            Button {
                                onOpenSettings()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "heart.fill")
                                    Text("Open Health App")
                                }
                                .font(AppFont.labelMedium)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.backgroundTertiary)
                                .foregroundStyle(Color.accentSecondary)
                                .clipShape(Capsule())
                            }

                            Text("In the Health app, tap your profile icon (top-right) → Apps → AI Fitness Coach")
                                .font(AppFont.captionSmall)
                                .foregroundStyle(Color.textTertiary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 32)
                    } else if !isRequesting {
                        Text("We'll sync your wellness data (HRV, sleep, recovery) from Apple Health")
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }
            }

            Spacer()
        }
        .padding()
        .background(Color.backgroundPrimary)
    }
}

// MARK: - Page 2: TrainingPeaks Import

struct TrainingPeaksImportPage: View {
    @Binding var showingFilePicker: Bool
    let isImporting: Bool
    let importResult: CSVImportResult?
    let importError: String?
    let csvPreview: CSVImportPreview?
    let onSkip: () -> Void
    let onContinue: () -> Void
    let onConfirmImport: () async -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Color.accentPrimary)

            Text("Import Workout History")
                .font(AppFont.displaySmall)
                .foregroundStyle(Color.textPrimary)

            Text("Get accurate TSS, IF, and training zones by importing your workout history from TrainingPeaks")
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            // Benefits
            VStack(spacing: 12) {
                TPBenefitRow(icon: "chart.xyaxis.line", title: "Accurate PMC", subtitle: "TSS calculated by TrainingPeaks")
                TPBenefitRow(icon: "speedometer", title: "Power & HR Zones", subtitle: "Time-in-zone data included")
                TPBenefitRow(icon: "person.fill.checkmark", title: "Subjective Data", subtitle: "RPE and feeling metrics")
            }
            .padding(.horizontal, 32)

            Spacer()

            // Import status
            if isImporting {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(Color.accentPrimary)
                    Text("Importing workouts...")
                        .font(AppFont.labelMedium)
                        .foregroundStyle(Color.textSecondary)
                }
            } else if let result = importResult {
                // Success state
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(result.importedCount) workouts imported")
                            .font(AppFont.labelMedium)
                            .foregroundStyle(.green)
                    }

                    if let range = result.dateRange {
                        Text(formatDateRange(range))
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
                .padding()
                .cardBackground()
                .padding(.horizontal, 32)
            } else if let preview = csvPreview, importResult == nil {
                // Preview state - show workouts to import
                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundStyle(Color.accentPrimary)
                        Text("\(preview.newWorkoutsCount) workouts to import")
                            .font(AppFont.labelMedium)
                            .foregroundStyle(Color.textPrimary)
                    }

                    if let range = preview.dateRangeFormatted {
                        Text(range)
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.textTertiary)
                    }

                    if preview.duplicatesCount > 0 {
                        Text("\(preview.duplicatesCount) duplicates will be skipped")
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.textTertiary)
                    }

                    Text("Total TSS: \(String(format: "%.0f", preview.totalTSS))")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding()
                .cardBackground()
                .padding(.horizontal, 32)
            } else if let error = importError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(AppFont.captionSmall)
                        .foregroundStyle(.orange)
                }
                .padding(.horizontal, 32)
            }

            // Buttons
            VStack(spacing: 12) {
                if let preview = csvPreview, importResult == nil {
                    // Confirm Import button (preview available)
                    Button {
                        Task { await onConfirmImport() }
                    } label: {
                        Text("Import \(preview.newWorkoutsCount) Workouts")
                            .font(AppFont.labelLarge)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(preview.isEmpty ? Color.gray : Color.accentPrimary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                    }
                    .disabled(isImporting || preview.isEmpty)
                    .padding(.horizontal, 32)

                    // Skip button
                    Button {
                        onSkip()
                    } label: {
                        Text("Skip for now")
                            .font(AppFont.labelMedium)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .disabled(isImporting)
                } else if importResult == nil {
                    // Import button (no preview yet)
                    Button {
                        showingFilePicker = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.badge.plus")
                            Text("Select CSV File")
                        }
                        .font(AppFont.labelLarge)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                    }
                    .disabled(isImporting)
                    .padding(.horizontal, 32)

                    // Skip button
                    Button {
                        onSkip()
                    } label: {
                        Text("Skip for now")
                            .font(AppFont.labelMedium)
                            .foregroundStyle(Color.textTertiary)
                    }
                    .disabled(isImporting)
                } else {
                    // Continue button after successful import
                    Button {
                        onContinue()
                    } label: {
                        Text("Continue")
                            .font(AppFont.labelLarge)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentPrimary)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                    }
                    .padding(.horizontal, 32)
                }
            }

            // How to export help text
            if importResult == nil && !isImporting {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("1. Log in to trainingpeaks.com")
                        Text("2. Go to Calendar view")
                        Text("3. Click gear icon → Export Workouts")
                        Text("4. Choose date range and export as CSV")
                    }
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
                    .padding(.top, 8)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.circle")
                        Text("How to export from TrainingPeaks")
                    }
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, 40)
            }

            Spacer()
        }
        .padding()
        .background(Color.backgroundPrimary)
    }

    private func formatDateRange(_ range: ClosedRange<Date>) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: range.lowerBound)) - \(formatter.string(from: range.upperBound))"
    }
}

struct TPBenefitRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.labelLarge)
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(AppFont.captionLarge)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()
        }
    }
}

struct OnboardingFeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentPrimary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.labelLarge)
                    .foregroundStyle(Color.textPrimary)
                Text(subtitle)
                    .font(AppFont.captionLarge)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()
        }
    }
}

// MARK: - Page 3: Sync Progress

struct SyncProgressPage: View {
    let isSyncing: Bool
    let isTransitioning: Bool
    let progress: SyncProgress
    let detectedThresholds: DetectedThresholds?
    let error: String?
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if isSyncing || progress.phase != .complete {
                // Syncing state (auto-started)
                syncingView
            } else {
                // Complete state
                completeView
            }

            Spacer()
        }
        .padding()
        .background(Color.backgroundPrimary)
    }

    @ViewBuilder
    private var syncingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.accentPrimary)

            Text(syncPhaseText)
                .font(AppFont.labelLarge)
                .foregroundStyle(Color.textPrimary)

            if progress.totalWorkouts > 0 {
                VStack(spacing: 8) {
                    Text("\(progress.processedWorkouts) workouts ready")
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }

        Text("Syncing wellness data and calculating fitness metrics...")
            .font(AppFont.captionLarge)
            .foregroundStyle(Color.textTertiary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
    }

    private var syncPhaseText: String {
        switch progress.phase {
        case .idle: return "Preparing..."
        case .fetchingWorkouts: return "Loading workouts..."
        case .processingWorkouts: return "Processing workouts..."
        case .calculatingPMC: return "Calculating fitness metrics..."
        case .syncingWellness: return "Syncing wellness data..."
        case .complete: return "Complete!"
        }
    }

    @ViewBuilder
    private var completeView: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 60))
            .foregroundStyle(.green)

        Text("You're All Set!")
            .font(AppFont.displaySmall)
            .foregroundStyle(Color.textPrimary)

        // Summary
        VStack(spacing: 12) {
            if progress.processedWorkouts > 0 {
                SummaryRow(label: "Workouts ready", value: "\(progress.processedWorkouts)")

                if !progress.workoutsByType.isEmpty {
                    ForEach(Array(progress.workoutsByType.sorted { $0.value > $1.value }.prefix(3)), id: \.key) { category, count in
                        SummaryRow(
                            label: category.rawValue,
                            value: "\(count)",
                            icon: category.icon,
                            color: category.themeColor
                        )
                    }
                }
            } else {
                // No workouts imported
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(Color.textTertiary)
                    Text("No workouts imported yet")
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.textTertiary)
                }
                Text("Import workouts from TrainingPeaks in Settings")
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding()
        .cardBackground()
        .padding(.horizontal, 32)

        // Detected thresholds
        if let thresholds = detectedThresholds, thresholds.hasAnyEstimates {
            VStack(alignment: .leading, spacing: 8) {
                Text("Auto-detected thresholds")
                    .font(AppFont.labelSmall)
                    .foregroundStyle(Color.textTertiary)

                if let ftp = thresholds.estimatedFTP {
                    ThresholdRow(label: "Cycling FTP", value: "\(ftp) W")
                }
                if let runFtp = thresholds.estimatedRunningFTP {
                    ThresholdRow(label: "Running FTP", value: "\(runFtp) W")
                }
                if let lthr = thresholds.estimatedLTHR {
                    ThresholdRow(label: "Threshold HR", value: "\(lthr) bpm")
                }
                if let pace = thresholds.thresholdPaceFormatted {
                    ThresholdRow(label: "Threshold Pace", value: pace)
                }
            }
            .padding()
            .cardBackground()
            .padding(.horizontal, 32)

            Text("You can adjust these in Settings")
                .font(AppFont.captionSmall)
                .foregroundStyle(Color.textTertiary)
        }

        if let error {
            Text(error)
                .font(AppFont.captionSmall)
                .foregroundStyle(.red)
                .padding()
        }

        Spacer()

        Button {
            onComplete()
        } label: {
            HStack(spacing: 8) {
                if isTransitioning {
                    ProgressView()
                        .tint(.white)
                }
                Text(isTransitioning ? "Saving..." : "Get Started")
            }
            .font(AppFont.labelLarge)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isTransitioning ? Color.gray : Color.accentPrimary)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        }
        .disabled(isTransitioning)
        .padding(.horizontal, 32)
    }
}

struct SummaryRow: View {
    let label: String
    let value: String
    var icon: String? = nil
    var color: Color = .textPrimary

    var body: some View {
        HStack {
            if let icon {
                Image(systemName: icon)
                    .foregroundStyle(color)
                    .frame(width: 24)
            }
            Text(label)
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.labelLarge)
                .foregroundStyle(color)
        }
    }
}

struct ThresholdRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(AppFont.captionLarge)
                .foregroundStyle(Color.textSecondary)
            Spacer()
            Text(value)
                .font(AppFont.labelMedium)
                .foregroundStyle(Color.accentPrimary)
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .modelContainer(for: [AthleteProfile.self, DailyMetrics.self, WorkoutRecord.self], inMemory: true)
        .environment(HealthKitService())
}
