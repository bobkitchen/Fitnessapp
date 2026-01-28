import SwiftUI
import SwiftData

/// Settings view for managing profile, thresholds, and app configuration
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [AthleteProfile]

    @State private var showingAPIKeySheet = false
    @State private var showingTPImportSheet = false
    @State private var showingAboutSheet = false
    @State private var accountBalance: String?
    @State private var isLoadingBalance = false
    @State private var balanceError: AppError?

    private var profile: AthleteProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            List {
                // Profile Section
                profileSection

                // Thresholds Section
                thresholdsSection

                // Data Section
                dataSection

                // AI Coaching Section
                aiCoachingSection

                // About Section
                aboutSection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingAPIKeySheet) {
                APIKeySettingsView()
            }
            .sheet(isPresented: $showingTPImportSheet) {
                TPWorkoutImportView()
            }
            .sheet(isPresented: $showingAboutSheet) {
                AboutView()
            }
        }
    }

    // MARK: - Profile Section

    @ViewBuilder
    private var profileSection: some View {
        Section("Profile") {
            if let profile {
                NavigationLink {
                    ProfileEditView(profile: profile)
                } label: {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .font(.title)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading) {
                            Text(profile.name.isEmpty ? "Add Your Name" : profile.name)
                                .font(.headline)
                            if let age = profile.age {
                                Text("\(age) years old")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Button("Create Profile") {
                    createProfile()
                }
            }
        }
    }

    // MARK: - Thresholds Section

    @ViewBuilder
    private var thresholdsSection: some View {
        Section("Training Thresholds") {
            if let profile {
                NavigationLink {
                    ThresholdEditView(profile: profile)
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        thresholdRow(title: "Cycling FTP", value: profile.ftpWatts.map { "\($0) W" })
                        thresholdRow(title: "Running FTP", value: profile.runningFTPWatts.map { "\($0) W" })
                        thresholdRow(title: "Threshold Pace", value: profile.thresholdPaceFormatted)
                        thresholdRow(title: "Threshold HR", value: "\(profile.thresholdHeartRate) bpm")
                        thresholdRow(title: "Max HR", value: "\(profile.maxHeartRate) bpm")
                    }
                }
            } else {
                Text("Create a profile first")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func thresholdRow(title: String, value: String?) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value ?? "Not set")
                .font(.subheadline)
                .foregroundStyle(value != nil ? .primary : .secondary)
        }
    }

    // MARK: - Data Section

    @ViewBuilder
    private var dataSection: some View {
        Section("Data & Sync") {
            NavigationLink {
                HealthKitSettingsView()
            } label: {
                Label("Apple Health", systemImage: "heart.fill")
            }

            Button {
                showingTPImportSheet = true
            } label: {
                HStack {
                    Label("Import TrainingPeaks Workout", systemImage: "link.badge.plus")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            NavigationLink {
                DataManagementView()
            } label: {
                Label("Data Management", systemImage: "externaldrive")
            }
        }
    }

    // MARK: - AI Coaching Section

    @ViewBuilder
    private var aiCoachingSection: some View {
        Section("AI Coach") {
            Button {
                showingAPIKeySheet = true
            } label: {
                HStack {
                    Label("API Key", systemImage: "key.fill")
                    Spacer()
                    if hasAPIKey {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Text("Not configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Account Balance
            if hasAPIKey {
                HStack {
                    Label("Account Balance", systemImage: "creditcard")
                    Spacer()
                    if isLoadingBalance {
                        ProgressView()
                            .controlSize(.small)
                    } else if let balance = accountBalance {
                        Text(balance)
                            .foregroundStyle(.secondary)
                    } else if balanceError != nil {
                        Button {
                            Task { await fetchAccountBalance() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text("Retry")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text("--")
                            .foregroundStyle(.secondary)
                    }
                }
                .task {
                    await fetchAccountBalance()
                }
            }

            NavigationLink {
                ModelSelectionView()
            } label: {
                Label("Default Model", systemImage: "cpu")
            }

            NavigationLink {
                CoachingPreferencesView()
            } label: {
                Label("Coaching Preferences", systemImage: "slider.horizontal.3")
            }

            NavigationLink {
                MemoriesManagementView()
            } label: {
                Label("Coach Memory", systemImage: "brain")
            }
        }
    }

    private func fetchAccountBalance() async {
        guard !isLoadingBalance else { return }
        isLoadingBalance = true
        balanceError = nil
        defer { isLoadingBalance = false }

        do {
            let service = OpenRouterService()
            let credits = try await service.fetchCredits()
            accountBalance = credits.formattedBalance
            balanceError = nil
        } catch {
            accountBalance = nil
            balanceError = error.toAppError()
        }
    }

    // MARK: - About Section

    @ViewBuilder
    private var aboutSection: some View {
        Section("About") {
            Button {
                showingAboutSheet = true
            } label: {
                Label("About This App", systemImage: "info.circle")
            }

            Link(destination: URL(string: "https://github.com")!) {
                Label("Privacy Policy", systemImage: "hand.raised")
            }

            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helper Methods

    private var hasAPIKey: Bool {
        // Check Keychain for API key
        UserDefaults.standard.bool(forKey: .hasOpenRouterAPIKey)
    }

    private func createProfile() {
        let newProfile = AthleteProfile()
        modelContext.insert(newProfile)
    }
}

// MARK: - Profile Edit View

struct ProfileEditView: View {
    @Bindable var profile: AthleteProfile
    @Environment(\.dismiss) private var dismiss
    @State private var isSyncingFromHealth = false
    @State private var healthSyncMessage: String?

    private let healthKitService = HealthKitService()

    var body: some View {
        Form {
            Section("Basic Info") {
                TextField("Name", text: $profile.name)

                DatePicker("Birth Date",
                          selection: Binding(
                            get: { profile.birthDate ?? Date() },
                            set: { profile.birthDate = $0 }
                          ),
                          displayedComponents: .date)
            }

            Section("Body Metrics") {
                HStack {
                    Text("Weight")
                    Spacer()
                    TextField("kg", value: $profile.weightKg, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("kg")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Height")
                    Spacer()
                    TextField("cm", value: $profile.heightCm, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("cm")
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await syncFromHealth()
                    }
                } label: {
                    HStack {
                        Label("Sync from Apple Health", systemImage: "heart.fill")
                        Spacer()
                        if isSyncingFromHealth {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                .disabled(isSyncingFromHealth)

                if let message = healthSyncMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Equipment") {
                Toggle("Cycling Power Meter", isOn: $profile.hasCyclingPowerMeter)
                Toggle("Running Power Meter", isOn: $profile.hasRunningPowerMeter)
            }

            Section("Primary Sport") {
                Picker("Primary Sport", selection: Binding(
                    get: { profile.primarySport ?? "triathlon" },
                    set: { profile.primarySport = $0 }
                )) {
                    Text("Triathlon").tag("triathlon")
                    Text("Cycling").tag("cycling")
                    Text("Running").tag("running")
                    Text("Swimming").tag("swimming")
                    Text("General Fitness").tag("general")
                }
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func syncFromHealth() async {
        isSyncingFromHealth = true
        healthSyncMessage = nil
        defer { isSyncingFromHealth = false }

        do {
            let healthData = try await healthKitService.fetchProfileData()
            var updatedFields: [String] = []

            // Update birth date if available and not already set
            // Use fetchDateOfBirth() directly to get exact date, not reconstructed from age
            if profile.birthDate == nil {
                if let dateOfBirth = try? healthKitService.fetchDateOfBirth() {
                    profile.birthDate = dateOfBirth
                    updatedFields.append("birth date")
                }
            }

            // Update weight if available
            if let weight = healthData.weightKg {
                profile.weightKg = weight
                updatedFields.append("weight")
            }

            // Update height if available
            if let height = healthData.heightCm {
                profile.heightCm = height
                updatedFields.append("height")
            }

            if updatedFields.isEmpty {
                healthSyncMessage = "No data found in Apple Health"
            } else {
                healthSyncMessage = "Updated: \(updatedFields.joined(separator: ", "))"
            }
        } catch {
            healthSyncMessage = "Could not read from Apple Health"
        }
    }
}

// MARK: - Threshold Edit View

struct ThresholdEditView: View {
    @Bindable var profile: AthleteProfile

    var body: some View {
        Form {
            Section("Cycling") {
                HStack {
                    Text("FTP")
                    Spacer()
                    TextField("Watts", value: $profile.ftpWatts, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("W")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Running") {
                HStack {
                    Text("Running FTP")
                    Spacer()
                    TextField("Watts", value: $profile.runningFTPWatts, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("W")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Threshold Pace")
                    Spacer()
                    TextField("sec/km", value: $profile.thresholdPaceSecondsPerKm, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("s/km")
                        .foregroundStyle(.secondary)
                }

                if let formatted = profile.thresholdPaceFormatted {
                    Text("= \(formatted)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Swimming") {
                HStack {
                    Text("Threshold Pace")
                    Spacer()
                    TextField("sec/100m", value: $profile.swimThresholdPacePer100m, format: .number)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("s/100m")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Heart Rate") {
                HStack {
                    Text("Threshold HR (LTHR)")
                    Spacer()
                    TextField("bpm", value: $profile.thresholdHeartRate, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("bpm")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Max HR")
                    Spacer()
                    TextField("bpm", value: $profile.maxHeartRate, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("bpm")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Resting HR")
                    Spacer()
                    TextField("bpm", value: $profile.restingHeartRate, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                    Text("bpm")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Text("These values are used to calculate TSS and training zones. Update them after testing or when your fitness changes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Training Thresholds")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Placeholder Views

struct HealthKitSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService
    @Query private var profiles: [AthleteProfile]
    @Query private var workouts: [WorkoutRecord]

    @State private var workoutSyncService: WorkoutSyncService?
    @State private var workoutCounts: WorkoutCounts?
    @State private var isResyncConfirmPresented = false

    private var profile: AthleteProfile? { profiles.first }

    var body: some View {
        List {
            // Connection Status
            connectionSection

            // Sync Status
            syncStatusSection

            // Workout Statistics
            if let counts = workoutCounts {
                workoutStatsSection(counts)
            }

            // Data Quality
            dataQualitySection

            // Actions
            actionsSection
        }
        .navigationTitle("Apple Health")
        .onAppear {
            workoutSyncService = WorkoutSyncService(healthKitService: healthKitService)
            updateCounts()
        }
        .alert("Full Resync", isPresented: $isResyncConfirmPresented) {
            Button("Cancel", role: .cancel) { }
            Button("Resync", role: .destructive) {
                Task { await performFullResync() }
            }
        } message: {
            Text("This will clear all workout data and re-import 12 months of history from Apple Health. This may take a few minutes.")
        }
    }

    // MARK: - Connection Section

    @ViewBuilder
    private var connectionSection: some View {
        Section("Connection") {
            HStack {
                Label("Apple Health", systemImage: "heart.fill")
                    .foregroundStyle(.red)
                Spacer()
                if healthKitService.isAuthorized {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connected")
                            .foregroundStyle(.green)
                    }
                    .font(.subheadline)
                } else {
                    Text("Not Connected")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }

            if let error = healthKitService.authorizationError {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Sync Status Section

    @ViewBuilder
    private var syncStatusSection: some View {
        Section("Sync Status") {
            if let syncService = workoutSyncService {
                if syncService.isSyncing {
                    // Show progress
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text(syncService.syncProgress.statusText)
                                .font(.subheadline)
                        }

                        if syncService.syncProgress.totalWorkouts > 0 {
                            ProgressView(value: syncService.syncProgress.progressPercent)
                                .tint(.blue)

                            Text("\(syncService.syncProgress.processedWorkouts) of \(syncService.syncProgress.totalWorkouts) workouts")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                } else {
                    // Show last sync info
                    HStack {
                        Text("Last Sync")
                        Spacer()
                        if let lastSync = syncService.lastSyncDate {
                            Text(lastSync, style: .relative)
                                .foregroundStyle(.secondary)
                        } else if let statsDate = syncService.syncStatistics.lastSyncDate {
                            Text(statsDate, style: .relative)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never")
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let error = syncService.syncError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Workout Stats Section

    @ViewBuilder
    private func workoutStatsSection(_ counts: WorkoutCounts) -> some View {
        Section("Imported Workouts") {
            // Total count
            HStack {
                Label("Total Workouts", systemImage: "figure.run")
                Spacer()
                Text("\(counts.total)")
                    .fontWeight(.semibold)
                    .foregroundStyle(.blue)
            }

            // Date range
            if let range = counts.dateRangeFormatted {
                HStack {
                    Text("Date Range")
                    Spacer()
                    Text(range)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // By category
            if !counts.byCategory.isEmpty {
                DisclosureGroup("By Activity Type") {
                    ForEach(Array(counts.byCategory.sorted { $0.value > $1.value }), id: \.key) { category, count in
                        HStack {
                            Image(systemName: category.icon)
                                .foregroundStyle(category.themeColor)
                                .frame(width: 24)
                            Text(category.rawValue)
                            Spacer()
                            Text("\(count)")
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
    }

    // MARK: - Data Quality Section

    @ViewBuilder
    private var dataQualitySection: some View {
        if let counts = workoutCounts, !counts.byTSSType.isEmpty {
            Section("Data Quality") {
                ForEach(Array(counts.byTSSType.sorted { $0.value > $1.value }), id: \.key) { tssType, count in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tssType.displayName)
                                .font(.subheadline)
                            Text(tssType.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(count)")
                            .foregroundStyle(tssType.qualityColor)
                            .fontWeight(.medium)
                    }
                }

                if let total = workoutCounts?.total, total > 0 {
                    let powerCount = counts.byTSSType[.power, default: 0] + counts.byTSSType[.runningPower, default: 0]
                    let powerPercent = Double(powerCount) / Double(total) * 100

                    HStack {
                        Text("Power Data Coverage")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0f%%", powerPercent))
                            .foregroundStyle(powerPercent > 50 ? .green : .orange)
                            .fontWeight(.medium)
                    }
                }
            }
        }
    }

    // MARK: - Actions Section

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            Button {
                Task { await performIncrementalSync() }
            } label: {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(workoutSyncService?.isSyncing == true || !healthKitService.isAuthorized)

            Button {
                isResyncConfirmPresented = true
            } label: {
                Label("Full Historical Resync", systemImage: "arrow.counterclockwise")
            }
            .disabled(workoutSyncService?.isSyncing == true || !healthKitService.isAuthorized)
        }

        // Strava Integration Section
        StravaSettingsSection()

        // TSS Learning Section
        Section("TSS Accuracy") {
            TSSAccuracyCard()
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        }

        // Health Permissions Section - always visible
        Section("Health Permissions") {
            Button {
                Task { await healthKitService.requestAuthorization() }
            } label: {
                Label("Request Health Access", systemImage: "heart.text.square")
            }

            Button {
                healthKitService.openHealthAppSettings()
            } label: {
                Label("Open Health App Settings", systemImage: "arrow.up.forward.app")
            }

            if !healthKitService.isAuthorized {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Health access not granted. Tap 'Request Health Access' or open the Health app to enable permissions for AI Fitness Coach.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section {
            Text("If workouts aren't syncing, open the Health app → Browse → tap a data type → Data Sources & Access → enable AI Fitness Coach.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func updateCounts() {
        workoutCounts = workoutSyncService?.getWorkoutCounts(modelContext: modelContext)
    }

    private func performIncrementalSync() async {
        await workoutSyncService?.performIncrementalSync(modelContext: modelContext, profile: profile)
        updateCounts()
    }

    private func performFullResync() async {
        // Clear existing workouts
        for workout in workouts {
            modelContext.delete(workout)
        }
        try? modelContext.save()

        // Perform fresh sync
        await workoutSyncService?.performInitialSync(modelContext: modelContext, profile: profile)
        updateCounts()
    }
}

struct DataManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var workouts: [WorkoutRecord]
    @Query private var metrics: [DailyMetrics]

    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            Section("Storage") {
                HStack {
                    Label("Workouts", systemImage: "figure.run")
                    Spacer()
                    Text("\(workouts.count) records")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Label("Daily Metrics", systemImage: "chart.line.uptrend.xyaxis")
                    Spacer()
                    Text("\(metrics.count) days")
                        .foregroundStyle(.secondary)
                }

                if let earliest = workouts.map({ $0.startDate }).min(),
                   let latest = workouts.map({ $0.startDate }).max() {
                    HStack {
                        Text("Date Range")
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(earliest, style: .date)
                            Text("to \(latest, style: .date)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button("Export Data", role: .none) {
                    // Export functionality
                }

                Button("Clear All Data", role: .destructive) {
                    showingClearConfirmation = true
                }
            }
        }
        .navigationTitle("Data Management")
        .alert("Clear All Data?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                clearAllData()
            }
        } message: {
            Text("This will permanently delete all workouts and metrics. You can re-sync from Apple Health afterward.")
        }
    }

    private func clearAllData() {
        for workout in workouts {
            modelContext.delete(workout)
        }
        for metric in metrics {
            modelContext.delete(metric)
        }
        try? modelContext.save()
    }
}

struct ModelSelectionView: View {
    @AppStorage("defaultAIModel") private var defaultModel = "anthropic/claude-sonnet-4-5-20250514"

    let models = [
        ("anthropic/claude-opus-4-5-20251101", "Claude Opus 4.5", "Highest quality"),
        ("anthropic/claude-sonnet-4-5-20250514", "Claude Sonnet 4.5", "Best balance"),
        ("openai/gpt-5.2", "GPT-5.2", "OpenAI's latest"),
        ("openai/gpt-4o", "GPT-4o", "Fast, high quality"),
        ("google/gemini-2.5-pro", "Gemini 2.5 Pro", "Google's latest"),
        ("meta-llama/llama-3.3-70b-instruct:free", "Llama 3.3 70B (Free)", "Powerful, free"),
        ("google/gemini-2.0-flash-exp:free", "Gemini 2.0 Flash (Free)", "Fast, free")
    ]

    var body: some View {
        List {
            Section("Default Model") {
                ForEach(models, id: \.0) { model in
                    Button {
                        defaultModel = model.0
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.1)
                                Text(model.2)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if defaultModel == model.0 {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section {
                Text("You can also select a different model for each chat session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("AI Model")
    }
}

struct CoachingPreferencesView: View {
    @AppStorage("coachingTone") private var tone = "balanced"
    @AppStorage("includeScienceExplanations") private var includeScience = true
    @AppStorage("suggestAlternatives") private var suggestAlternatives = true

    var body: some View {
        List {
            Section("Coaching Style") {
                Picker("Tone", selection: $tone) {
                    Text("Encouraging").tag("encouraging")
                    Text("Balanced").tag("balanced")
                    Text("Direct").tag("direct")
                }
            }

            Section("Content") {
                Toggle("Include Science Explanations", isOn: $includeScience)
                Toggle("Suggest Workout Alternatives", isOn: $suggestAlternatives)
            }
        }
        .navigationTitle("Coaching Preferences")
    }
}

struct APIKeySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    @State private var isVerifying = false
    @State private var isSaving = false
    @State private var saveError: AppError?
    @State private var verificationResult: Bool?

    var body: some View {
        NavigationStack {
            Form {
                Section("OpenRouter API Key") {
                    SecureField("API Key", text: $apiKey)
                        .textContentType(.password)

                    if let result = verificationResult {
                        HStack {
                            Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result ? .green : .red)
                            Text(result ? "Valid API key" : "Invalid API key")
                        }
                    }

                    if let error = saveError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(error.recoverySuggestion ?? "Could not save API key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Get API Key from OpenRouter") {
                        if let url = URL(string: "https://openrouter.ai/keys") {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                Section {
                    Text("Your API key is stored securely in the iOS Keychain and never leaves your device except to authenticate with OpenRouter.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAPIKey()
                    }
                    .disabled(apiKey.isEmpty || isSaving)
                }
            }
        }
    }

    private func saveAPIKey() {
        isSaving = true
        saveError = nil
        defer { isSaving = false }

        do {
            try KeychainService.saveOpenRouterAPIKey(apiKey)
            UserDefaults.standard.set(true, forKey: .hasOpenRouterAPIKey)
            dismiss()
        } catch {
            saveError = .storageError(underlying: error)
            verificationResult = false
        }
    }
}

/// DEPRECATED: Screenshot-based calibration view
/// Kept for backwards compatibility with users who have existing workflows
/// Prefer using TPWorkoutImportView for new calibrations
struct CalibrationSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "scope")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("TrainingPeaks Calibration")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Share a screenshot of your TrainingPeaks PMC chart to calibrate your CTL/ATL/TSB values with your existing training history.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Text("Use the iOS Share Sheet to share a screenshot, then select this app.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                // New recommendation
                VStack(spacing: 8) {
                    Divider()
                    HStack {
                        Image(systemName: "lightbulb.fill")
                            .foregroundStyle(.yellow)
                        Text("Tip: For easier calibration, share a workout directly from TrainingPeaks instead of a screenshot.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Calibration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.blue)

                    Text("AI Fitness Coach")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Version 1.0.0")
                        .foregroundStyle(.secondary)

                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Text("An intelligent fitness coaching app for multi-sport athletes.")
                            .font(.subheadline)

                        Text("Features:")
                            .font(.headline)
                            .padding(.top)

                        FeatureRow(icon: "chart.line.uptrend.xyaxis", text: "PMC tracking with CTL/ATL/TSB")
                        FeatureRow(icon: "heart.fill", text: "Comprehensive wellness monitoring")
                        FeatureRow(icon: "bubble.left.fill", text: "AI-powered coaching advice")
                        FeatureRow(icon: "applewatch", text: "Apple Health integration")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .padding()
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Memories Management View

struct MemoriesManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \UserMemory.createdAt, order: .reverse) private var memories: [UserMemory]

    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            if memories.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "brain")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        Text("No Memories Yet")
                            .font(.headline)

                        Text("When you share information with your AI Coach (like vacation plans, injuries, or goals), it will automatically remember relevant details for future conversations.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
            } else {
                // Active memories
                let activeMemories = memories.filter { $0.isActive }
                if !activeMemories.isEmpty {
                    Section("Active") {
                        ForEach(activeMemories) { memory in
                            MemoryRow(memory: memory)
                        }
                        .onDelete { indexSet in
                            deleteMemories(at: indexSet, from: activeMemories)
                        }
                    }
                }

                // Expired memories
                let expiredMemories = memories.filter { !$0.isActive }
                if !expiredMemories.isEmpty {
                    Section("Expired") {
                        ForEach(expiredMemories) { memory in
                            MemoryRow(memory: memory)
                                .opacity(0.6)
                        }
                        .onDelete { indexSet in
                            deleteMemories(at: indexSet, from: expiredMemories)
                        }
                    }
                }

                // Clear all button
                Section {
                    Button("Clear All Memories", role: .destructive) {
                        showingClearConfirmation = true
                    }
                }
            }
        }
        .navigationTitle("Coach Memory")
        .alert("Clear All Memories?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                clearAllMemories()
            }
        } message: {
            Text("This will delete all saved memories. Your AI Coach will no longer remember past information you've shared.")
        }
    }

    private func deleteMemories(at indexSet: IndexSet, from memoryList: [UserMemory]) {
        for index in indexSet {
            let memory = memoryList[index]
            modelContext.delete(memory)
        }
        try? modelContext.save()
    }

    private func clearAllMemories() {
        for memory in memories {
            modelContext.delete(memory)
        }
        try? modelContext.save()
    }
}

struct MemoryRow: View {
    let memory: UserMemory

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: memory.category.icon)
                    .foregroundStyle(.blue)
                    .frame(width: 20)

                Text(memory.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let expiresAt = memory.expiresAt {
                    if memory.isActive {
                        Text("expires \(expiresAt, style: .relative)")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    } else {
                        Text("expired")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                } else {
                    Text("permanent")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }

            Text(memory.content)
                .font(.subheadline)

            Text("Added \(memory.createdAt, style: .relative)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .modelContainer(for: [AthleteProfile.self, UserMemory.self], inMemory: true)
}
