//
//  FitnessAppApp.swift
//  FitnessApp
//
//  Created by Bob Kitchen on 1/17/26.
//

import SwiftUI
import SwiftData

// Make URL work with sheet(item:) binding
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

@main
struct FitnessAppApp: App {
    let modelContainer: ModelContainer

    @State private var healthKitService = HealthKitService()
    @State private var readinessState = ReadinessStateService()
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: .hasCompletedOnboarding)

    @State private var storageError: StorageError?

    init() {
        let schema = Schema([
            AthleteProfile.self,
            DailyMetrics.self,
            WorkoutRecord.self,
            CalibrationRecord.self,
            TSSScalingProfile.self,
            TSSCalibrationDataPoint.self,
            CoachingKnowledge.self,
            UserMemory.self
        ])

        // Use app's documents directory for SwiftData storage (not App Group)
        // App Group is reserved for Share Extension data sharing
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let storeURL = documentsURL.appendingPathComponent("FitnessApp.store")

        // Try persistent storage first, fall back to in-memory if corrupted
        do {
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none  // Can enable CloudKit later
            )

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            // Log the error for debugging
            print("[FitnessApp] ERROR: Failed to initialize persistent storage: \(error)")
            print("[FitnessApp] Falling back to in-memory storage. Data will not persist.")

            // Fall back to in-memory storage so the app remains functional
            do {
                let inMemoryConfig = ModelConfiguration(
                    schema: schema,
                    isStoredInMemoryOnly: true,
                    cloudKitDatabase: .none
                )
                modelContainer = try ModelContainer(
                    for: schema,
                    configurations: [inMemoryConfig]
                )
                // Note: We'll show the user an alert about this in the view
                _storageError = State(initialValue: .persistentStorageFailed(error))
            } catch {
                // If even in-memory fails, we have a serious problem
                fatalError("Could not initialize ModelContainer even with in-memory storage: \(error)")
            }
        }
    }

    /// Storage-related errors that can be shown to the user
    enum StorageError: Identifiable {
        case persistentStorageFailed(Error)

        var id: String {
            switch self {
            case .persistentStorageFailed: return "persistent_storage_failed"
            }
        }

        var title: String {
            "Storage Issue"
        }

        var message: String {
            switch self {
            case .persistentStorageFailed:
                return "Unable to access your saved data. The app is running with temporary storage. Your data from this session will not be saved. Try restarting the app or contact support if this persists."
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    MainTabView()
                        .environment(healthKitService)
                        .environment(readinessState)
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding)
                        .environment(healthKitService)
                        .environment(readinessState)
                }
            }
            .alert(item: $storageError) { error in
                Alert(
                    title: Text(error.title),
                    message: Text(error.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .modelContainer(modelContainer)
        .handlesExternalEvents(matching: Set(["*"]))
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @Environment(HealthKitService.self) private var healthKitService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab = 1  // Default to Today (center tab)

    // Calibration state
    @State private var pendingScreenshotURL: URL?
    @State private var calibrationResult: CalibrationRecord?
    @State private var showingCalibrationConfirmation = false

    // Workout import state (from Share Extension)
    @State private var showingTPImportView = false
    @State private var sharedWorkoutURL: String?

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                Tab("Coach", systemImage: "bubble.left.fill", value: 0) {
                    CoachView()
                }

                Tab("Today", systemImage: "figure.stand", value: 1) {
                    DashboardView()
                }

                Tab("Performance", systemImage: "waveform.path.ecg", value: 2) {
                    PerformanceView()
                }
            }
            .tabViewStyle(.tabBarOnly)

            // Calibration confirmation toast
            if showingCalibrationConfirmation {
                VStack {
                    CalibrationToast(result: calibrationResult)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .padding(.top, Spacing.xl)
            }
        }
        .task {
            // Initialize secrets in Keychain on first launch
            AppSecrets.initializeKeychainIfNeeded()

            await healthKitService.requestAuthorization()
            await syncProfileFromHealthKitIfNeeded()
            await seedKnowledgeBaseIfNeeded()
        }
        .onAppear {
            checkForSharedScreenshot()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .active {
                checkForSharedScreenshot()
            }
        }
        .onOpenURL { url in
            // Handle fitnesscoach:// URL scheme
            if url.scheme == "fitnesscoach" {
                switch url.host {
                case "calibrate":
                    // Legacy screenshot calibration flow
                    checkForSharedScreenshot()
                case "import-workout":
                    // New workout import flow (from Share Extension)
                    checkForSharedWorkout()
                default:
                    // Fallback - try both
                    checkForSharedScreenshot()
                    checkForSharedWorkout()
                }
            }
        }
        .sheet(isPresented: $showingTPImportView) {
            TPWorkoutImportView(prefilledURL: sharedWorkoutURL)
                .onDisappear {
                    clearSharedWorkout()
                }
        }
        .sheet(item: $pendingScreenshotURL) { url in
            CalibrationReviewView(
                screenshotURL: url,
                calibrationResult: $calibrationResult,
                onDismiss: {
                    clearSharedScreenshot()
                }
            )
        }
        .onChange(of: calibrationResult) { oldValue, newValue in
            if newValue != nil && newValue?.calibrationApplied == true {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    showingCalibrationConfirmation = true
                }
                // Auto-dismiss after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        showingCalibrationConfirmation = false
                        calibrationResult = nil
                    }
                }
            }
        }
    }

    private func checkForSharedScreenshot() {
        Task {
            let ocrService = ScreenshotOCRService()
            if let url = await ocrService.checkForSharedScreenshot() {
                await MainActor.run {
                    // Setting pendingScreenshotURL triggers the sheet via item binding
                    pendingScreenshotURL = url
                }
            }
        }
    }

    private func clearSharedScreenshot() {
        // Setting pendingScreenshotURL to nil dismisses the sheet
        pendingScreenshotURL = nil
        Task {
            let ocrService = ScreenshotOCRService()
            await ocrService.clearSharedScreenshot()
        }
    }

    /// Check for shared workout data from Share Extension
    private func checkForSharedWorkout() {
        guard let userDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) else {
            return
        }

        // Check if there's shared workout data
        guard let workoutData = userDefaults.dictionary(forKey: "sharedWorkout"),
              let timestamp = workoutData["timestamp"] as? Double else {
            return
        }

        // Only process if shared recently (within last 5 minutes)
        let sharedDate = Date(timeIntervalSince1970: timestamp)
        guard Date().timeIntervalSince(sharedDate) < 300 else {
            // Data is stale, clear it
            clearSharedWorkout()
            return
        }

        // Extract URL or text
        if let urlString = workoutData["url"] as? String {
            sharedWorkoutURL = urlString
        } else if let text = workoutData["text"] as? String {
            // Try to extract URL from text
            sharedWorkoutURL = extractURLFromText(text)
        }

        if sharedWorkoutURL != nil {
            // Show the TP import view
            showingTPImportView = true
        }
    }

    /// Clear shared workout data from App Group
    private func clearSharedWorkout() {
        sharedWorkoutURL = nil
        guard let userDefaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) else {
            return
        }
        userDefaults.removeObject(forKey: "sharedWorkout")
        userDefaults.removeObject(forKey: "sharedWorkoutDate")
    }

    /// Extract a URL from shared text
    private func extractURLFromText(_ text: String) -> String? {
        // Match TrainingPeaks URLs
        let patterns = [
            "https?://[\\w.]*trainingpeaks\\.com/[\\w/?=&-]+",
            "https?://tpks\\.ws/[\\w/?=&-]+"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if let matchRange = Range(match.range, in: text) {
                        return String(text[matchRange])
                    }
                }
            }
        }
        return nil
    }

    private func seedKnowledgeBaseIfNeeded() async {
        let importService = KnowledgeImportService(modelContext: modelContext)
        do {
            try await importService.seedKnowledgeIfNeeded()
        } catch {
            print("Failed to seed knowledge base: \(error)")
        }
    }

    /// Automatically sync profile data (age, height, weight) from HealthKit
    /// - Weight syncs every time (changes frequently)
    /// - Age and height sync only once (static values)
    private func syncProfileFromHealthKitIfNeeded() async {
        // Only sync if HealthKit is authorized
        guard healthKitService.isAuthorized else { return }

        do {
            let healthData = try await healthKitService.fetchProfileData()

            // Get or create profile
            let descriptor = FetchDescriptor<AthleteProfile>()
            let profiles = try modelContext.fetch(descriptor)
            let profile = profiles.first ?? {
                let newProfile = AthleteProfile()
                modelContext.insert(newProfile)
                return newProfile
            }()

            var didUpdate = false
            let hasInitialSync = UserDefaults.standard.bool(forKey: .hasSyncedProfileFromHealthKit)

            // Sync birth date only on first sync (age doesn't change)
            // Use fetchDateOfBirth() directly to get exact date, not reconstructed from age
            if !hasInitialSync, profile.birthDate == nil {
                if let dateOfBirth = try? healthKitService.fetchDateOfBirth() {
                    profile.birthDate = dateOfBirth
                    didUpdate = true
                }
            }

            // Sync height only on first sync (height rarely changes for adults)
            if !hasInitialSync, profile.heightCm == nil, let height = healthData.heightCm {
                profile.heightCm = height
                didUpdate = true
            }

            // Always sync weight (changes regularly)
            if let weight = healthData.weightKg {
                profile.weightKg = weight
                didUpdate = true
            }

            if didUpdate {
                try modelContext.save()
                print("[HealthKit] Synced profile data from Apple Health")
            }

            // Mark initial sync complete
            if !hasInitialSync {
                UserDefaults.standard.set(true, forKey: .hasSyncedProfileFromHealthKit)
            }

        } catch {
            print("[HealthKit] Failed to sync profile data: \(error)")
        }
    }
}

// MARK: - Calibration Toast

/// Toast notification showing calibration success
struct CalibrationToast: View {
    let result: CalibrationRecord?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.statusExcellent)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text("Calibration Applied")
                    .font(AppFont.labelLarge)
                    .foregroundStyle(Color.textPrimary)

                if let result {
                    Text(result.deltaSummary)
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.textSecondary)
                }
            }

            Spacer()
        }
        .padding(Spacing.md)
        .background(Color.backgroundTertiary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.large)
                .stroke(Color.statusExcellent.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
        .padding(.horizontal, Spacing.md)
    }
}

// MARK: - App Constants

enum AppConstants {
    static let appGroupIdentifier = "group.com.bobk.FitnessApp"
    static let bundleIdentifier = "com.bobk.FitnessApp"

    // PMC Constants
    static let ctlTimeConstant: Double = 42  // Days for CTL calculation
    static let atlTimeConstant: Double = 7   // Days for ATL calculation

    // Default values
    static let defaultCTL: Double = 0
    static let defaultATL: Double = 0

    // Thresholds
    static let calibrationThreshold: Double = 5  // Delta that triggers calibration

    // Date formatting
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter
    }()

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Preview Support

#Preview {
    MainTabView()
        .modelContainer(for: [
            AthleteProfile.self,
            DailyMetrics.self,
            WorkoutRecord.self,
            CalibrationRecord.self,
            TSSScalingProfile.self,
            TSSCalibrationDataPoint.self,
            CoachingKnowledge.self,
            UserMemory.self
        ], inMemory: true)
        .environment(HealthKitService())
        .environment(ReadinessStateService())
}
