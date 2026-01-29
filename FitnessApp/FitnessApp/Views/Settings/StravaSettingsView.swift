//
//  StravaSettingsView.swift
//  FitnessApp
//
//  Settings UI for Strava connection and sync.
//

import SwiftUI
import SwiftData

/// Full-page Strava settings view for NavigationLink destination
struct StravaSettingsView: View {
    var body: some View {
        List {
            StravaSettingsSection()
        }
        .navigationTitle("Strava")
    }
}

struct StravaSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var stravaService = StravaService()
    @State private var syncService: StravaSyncService?
    @State private var showingDisconnectAlert = false
    @State private var syncError: String?

    var body: some View {
        Section {
            if stravaService.isAuthenticated {
                connectedView
            } else {
                connectButton
            }
        } header: {
            Label("Strava", systemImage: "figure.run.circle")
        } footer: {
            Text("Strava is your primary workout source. Activities sync automatically when you open the app.")
        }
        .onAppear {
            syncService = StravaSyncService(stravaService: stravaService, modelContext: modelContext)
        }
        .alert("Disconnect Strava", isPresented: $showingDisconnectAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                stravaService.logout()
            }
        } message: {
            Text("Your workout data will remain, but new activities won't sync from Strava.")
        }
        .alert("Sync Error", isPresented: .init(
            get: { syncError != nil },
            set: { if !$0 { syncError = nil } }
        )) {
            Button("OK") { syncError = nil }
        } message: {
            Text(syncError ?? "An error occurred")
        }
    }

    // MARK: - Connected View

    @ViewBuilder
    private var connectedView: some View {
        // Profile row
        HStack {
            if let athlete = stravaService.athleteProfile {
                VStack(alignment: .leading, spacing: 2) {
                    Text(athlete.fullName.isEmpty ? "Strava Athlete" : athlete.fullName)
                        .font(.headline)
                    if let city = athlete.city {
                        Text(city)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Connected")
                    .font(.headline)
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }

        // Sync button
        Button {
            Task {
                await syncActivities()
            }
        } label: {
            HStack {
                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                Spacer()
                if let syncService, syncService.isSyncing {
                    ProgressView()
                        .controlSize(.small)
                } else if let result = syncService?.lastSyncResult {
                    Text(result.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(syncService?.isSyncing == true)

        // Auto-sync info
        HStack {
            Label("Auto-Sync", systemImage: "arrow.clockwise")
                .foregroundStyle(.secondary)
            Spacer()
            Text("Every hour on app open")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)

        // Last sync info (from persisted date)
        if let lastSync = StravaSyncService.lastSyncDate {
            HStack {
                Text("Last synced")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(lastSync, style: .relative)
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }

        // Disconnect button
        Button(role: .destructive) {
            showingDisconnectAlert = true
        } label: {
            Label("Disconnect Strava", systemImage: "minus.circle")
        }
    }

    // MARK: - Connect Button

    @ViewBuilder
    private var connectButton: some View {
        Button {
            Task {
                await connectStrava()
            }
        } label: {
            HStack {
                Image("strava-logo")  // You'll need to add this asset
                    .resizable()
                    .scaledToFit()
                    .frame(height: 20)
                    .opacity(0)  // Fallback if image not available

                Label("Connect with Strava", systemImage: "link")

                Spacer()

                if stravaService.isAuthenticating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(stravaService.isAuthenticating)
    }

    // MARK: - Actions

    private func connectStrava() async {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            return
        }

        do {
            try await stravaService.authenticate(presentationAnchor: window)
            // Auto-sync after connecting
            await syncActivities()
        } catch StravaError.userCancelled {
            // User cancelled - no error to show
        } catch {
            syncError = error.localizedDescription
        }
    }

    private func syncActivities() async {
        guard let syncService else { return }

        do {
            if StravaSyncService.lastSyncDate == nil {
                // First sync: fetch full 12-month history
                _ = try await syncService.syncAllActivities()
            } else {
                // Incremental sync
                _ = try await syncService.syncRecentActivities()
            }
        } catch {
            syncError = error.localizedDescription
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        Form {
            StravaSettingsSection()
        }
    }
    .modelContainer(for: WorkoutRecord.self, inMemory: true)
}
