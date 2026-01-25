import SwiftUI
import SwiftData
import UIKit

/// Streamlined 3-page onboarding flow
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthKitService.self) private var healthKitService

    @State private var currentPage = 0
    @State private var isRequestingHealthKit = false
    @State private var isSyncing = false
    @State private var syncProgress: SyncProgress = SyncProgress()
    @State private var detectedThresholds: DetectedThresholds?
    @State private var syncError: String?

    var body: some View {
        TabView(selection: $currentPage) {
            // Page 1: Welcome + HealthKit
            WelcomeHealthKitPage(
                isRequesting: $isRequestingHealthKit,
                isAuthorized: healthKitService.isAuthorized,
                hasAttemptedAuth: healthKitService.hasAttemptedAuthorization,
                authError: healthKitService.authorizationError,
                onRequestAccess: requestHealthKitAccess,
                onContinue: { currentPage = 1 },
                onOpenSettings: { healthKitService.openHealthAppSettings() }
            )
            .tag(0)

            // Page 2: Sync Progress
            SyncProgressPage(
                isSyncing: isSyncing,
                progress: syncProgress,
                detectedThresholds: detectedThresholds,
                error: syncError,
                onStartSync: startSync,
                onContinue: { currentPage = 2 }
            )
            .tag(1)

            // Page 3: Complete
            CompletionPage(onComplete: completeOnboarding)
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .interactiveDismissDisabled()
    }

    private func requestHealthKitAccess() {
        isRequestingHealthKit = true
        Task { @MainActor in
            await healthKitService.requestAuthorization()
            isRequestingHealthKit = false
        }
    }

    private func startSync() {
        isSyncing = true
        syncError = nil

        Task {
            // Create profile first
            let profile = AthleteProfile()
            modelContext.insert(profile)
            try? modelContext.save()

            // Start sync
            let syncService = WorkoutSyncService(healthKitService: healthKitService)

            await syncService.performInitialSync(modelContext: modelContext, profile: profile)

            // Update progress from service
            syncProgress = syncService.syncProgress

            if let error = syncService.syncError {
                syncError = error.localizedDescription
            }

            // Auto-detect thresholds
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
                try? modelContext.save()
            }

            isSyncing = false
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        hasCompletedOnboarding = true
    }
}

// MARK: - Page 1: Welcome + HealthKit

struct WelcomeHealthKitPage: View {
    @Binding var isRequesting: Bool
    let isAuthorized: Bool
    let hasAttemptedAuth: Bool
    let authError: Error?
    let onRequestAccess: () -> Void
    let onContinue: () -> Void
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
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Connected to Apple Health")
                            .foregroundStyle(.green)
                    }
                    .font(AppFont.labelLarge)

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
                        Text("Tap the button above to connect to Apple Health")
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

// MARK: - Page 2: Sync Progress

struct SyncProgressPage: View {
    let isSyncing: Bool
    let progress: SyncProgress
    let detectedThresholds: DetectedThresholds?
    let error: String?
    let onStartSync: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            if isSyncing {
                // Syncing state
                syncingView
            } else if progress.phase == .complete {
                // Complete state
                completeView
            } else {
                // Ready to sync state
                readyToSyncView
            }

            Spacer()
        }
        .padding()
        .background(Color.backgroundPrimary)
    }

    @ViewBuilder
    private var readyToSyncView: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 60))
            .foregroundStyle(Color.accentPrimary)

        Text("Import Your History")
            .font(AppFont.displaySmall)
            .foregroundStyle(Color.textPrimary)

        Text("We'll import 6 months of workouts from Apple Health and automatically detect your training thresholds.")
            .font(AppFont.bodyMedium)
            .foregroundStyle(Color.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)

        Spacer()

        Button {
            onStartSync()
        } label: {
            Text("Start Import")
                .font(AppFont.labelLarge)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.accentPrimary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        }
        .padding(.horizontal, 32)
    }

    @ViewBuilder
    private var syncingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Color.accentPrimary)

            Text(progress.statusText)
                .font(AppFont.labelLarge)
                .foregroundStyle(Color.textPrimary)

            if progress.totalWorkouts > 0 {
                VStack(spacing: 8) {
                    ProgressView(value: progress.progressPercent)
                        .tint(Color.accentPrimary)
                        .frame(width: 200)

                    Text("\(progress.processedWorkouts) of \(progress.totalWorkouts) workouts")
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }

        Text("This may take a few minutes...")
            .font(AppFont.captionLarge)
            .foregroundStyle(Color.textTertiary)
    }

    @ViewBuilder
    private var completeView: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 60))
            .foregroundStyle(.green)

        Text("Import Complete!")
            .font(AppFont.displaySmall)
            .foregroundStyle(Color.textPrimary)

        // Summary
        VStack(spacing: 12) {
            SummaryRow(label: "Workouts imported", value: "\(progress.processedWorkouts)")

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

// MARK: - Page 3: Completion

struct CompletionPage: View {
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(Color.accentSecondary)

            Text("You're All Set!")
                .font(AppFont.displaySmall)
                .foregroundStyle(Color.textPrimary)

            Text("Your AI fitness coach is ready to help you train smarter")
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            // Tips
            VStack(alignment: .leading, spacing: 16) {
                TipRow(number: 1, text: "Check the dashboard for your fitness status")
                TipRow(number: 2, text: "Ask the AI coach for personalized advice")
                TipRow(number: 3, text: "Adjust thresholds in Settings for accuracy")
            }
            .padding(.horizontal, 32)

            Spacer()

            Button {
                onComplete()
            } label: {
                Text("Get Started")
                    .font(AppFont.labelLarge)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding()
        .background(Color.backgroundPrimary)
    }
}

struct TipRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentSecondary)
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(AppFont.labelMedium)
                    .foregroundStyle(.white)
            }

            Text(text)
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)

            Spacer()
        }
    }
}

// MARK: - Preview

#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
        .modelContainer(for: [AthleteProfile.self, DailyMetrics.self, WorkoutRecord.self], inMemory: true)
        .environment(HealthKitService())
}
