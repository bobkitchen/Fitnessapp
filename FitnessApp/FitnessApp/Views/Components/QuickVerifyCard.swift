//
//  QuickVerifyCard.swift
//  FitnessApp
//
//  Quick-verify UI component for confirming or correcting TSS and PMC values.
//  Users can tap to confirm calculated values match TP, or edit to enter TP values.
//

import SwiftUI
import SwiftData

// MARK: - Quick Verify Card

struct QuickVerifyCard: View {
    @Bindable var workout: WorkoutRecord
    @Environment(\.modelContext) private var modelContext

    // Current PMC values (passed from parent)
    let currentCTL: Double
    let currentATL: Double
    let currentTSB: Double

    // Editing state
    @State private var isEditing = false
    @State private var editingField: EditingField?
    @State private var tssText: String = ""
    @State private var ctlText: String = ""
    @State private var atlText: String = ""
    @State private var tsbText: String = ""

    // Animation
    @State private var showConfirmation = false

    // Callback when values are verified
    var onVerified: ((WorkoutRecord) -> Void)?

    private enum EditingField {
        case tss, ctl, atl, tsb
    }

    var body: some View {
        VStack(spacing: Spacing.sm) {
            // Header
            HStack {
                Text("Verify with TrainingPeaks")
                    .font(AppFont.labelMedium)
                    .foregroundStyle(Color.textSecondary)

                Spacer()

                if workout.tssVerificationStatus == .confirmed {
                    Label("Verified", systemImage: "checkmark.circle.fill")
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.statusExcellent)
                } else if workout.tssVerificationStatus == .corrected {
                    Label("Corrected", systemImage: "pencil.circle.fill")
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.accentPrimary)
                }
            }

            // Value fields
            HStack(spacing: Spacing.md) {
                verifyField(
                    label: "TSS",
                    calculatedValue: workout.tss,
                    userValue: workout.userEnteredTSS,
                    text: $tssText,
                    field: .tss,
                    format: "%.0f"
                )

                Divider()
                    .frame(height: 40)

                verifyField(
                    label: "CTL",
                    calculatedValue: currentCTL,
                    userValue: workout.userEnteredCTL,
                    text: $ctlText,
                    field: .ctl,
                    format: "%.0f"
                )

                verifyField(
                    label: "ATL",
                    calculatedValue: currentATL,
                    userValue: workout.userEnteredATL,
                    text: $atlText,
                    field: .atl,
                    format: "%.0f"
                )

                verifyField(
                    label: "TSB",
                    calculatedValue: currentTSB,
                    userValue: workout.userEnteredTSB,
                    text: $tsbText,
                    field: .tsb,
                    format: "%.0f"
                )
            }

            // Action buttons
            if workout.tssVerificationStatus == .pending {
                HStack(spacing: Spacing.md) {
                    // Confirm button (values match TP)
                    Button {
                        confirmValues()
                    } label: {
                        Label("Matches TP", systemImage: "checkmark")
                            .font(AppFont.labelMedium)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.statusExcellent)

                    // Save corrections button (only show if editing)
                    if hasEdits {
                        Button {
                            saveCorrections()
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .font(AppFont.labelMedium)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentPrimary)
                    }
                }
            } else {
                // Already verified - show edit option
                Button {
                    resetToEditing()
                } label: {
                    Label("Edit Values", systemImage: "pencil")
                        .font(AppFont.captionLarge)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(Spacing.md)
        .background(Color.backgroundTertiary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(
                    workout.tssVerificationStatus == .confirmed ? Color.statusExcellent.opacity(0.3) :
                    workout.tssVerificationStatus == .corrected ? Color.accentPrimary.opacity(0.3) :
                    Color.clear,
                    lineWidth: 1
                )
        )
        .onAppear {
            initializeTextFields()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("TrainingPeaks verification")
        .accessibilityHint(workout.tssVerificationStatus == .pending ?
            "Enter your TrainingPeaks values to verify or tap Matches TP to confirm" :
            "Values have been verified")
    }

    // MARK: - Verify Field

    @ViewBuilder
    private func verifyField(
        label: String,
        calculatedValue: Double,
        userValue: Double?,
        text: Binding<String>,
        field: EditingField,
        format: String
    ) -> some View {
        let isCurrentlyEditing = editingField == field
        let displayValue = userValue ?? calculatedValue
        let hasDelta = userValue != nil && abs(userValue! - calculatedValue) > 0.5

        VStack(spacing: Spacing.xxxs) {
            Text(label)
                .font(AppFont.captionSmall)
                .foregroundStyle(Color.textTertiary)

            if isCurrentlyEditing {
                TextField("", text: text)
                    .font(AppFont.metricSmall)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 50)
                    .padding(.horizontal, Spacing.xs)
                    .padding(.vertical, Spacing.xxxs)
                    .background(Color.backgroundSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                    .onSubmit {
                        editingField = nil
                    }
            } else {
                Button {
                    editingField = field
                } label: {
                    Text(String(format: format, displayValue))
                        .font(AppFont.metricSmall)
                        .foregroundStyle(hasDelta ? Color.accentPrimary : Color.textPrimary)
                }
                .buttonStyle(.plain)
            }

            // Show delta if user corrected
            if hasDelta {
                let delta = userValue! - calculatedValue
                Text(String(format: "%+.0f", delta))
                    .font(AppFont.captionSmall)
                    .foregroundStyle(delta > 0 ? Color.statusExcellent : Color.statusLow)
            }
        }
        .frame(minWidth: 50)
    }

    // MARK: - Computed Properties

    private var hasEdits: Bool {
        let tssValue = Double(tssText)
        let ctlValue = Double(ctlText)
        let atlValue = Double(atlText)
        let tsbValue = Double(tsbText)

        return (tssValue != nil && abs(tssValue! - workout.tss) > 0.5) ||
               (ctlValue != nil && abs(ctlValue! - currentCTL) > 0.5) ||
               (atlValue != nil && abs(atlValue! - currentATL) > 0.5) ||
               (tsbValue != nil && abs(tsbValue! - currentTSB) > 0.5)
    }

    // MARK: - Actions

    private func initializeTextFields() {
        tssText = String(format: "%.0f", workout.userEnteredTSS ?? workout.tss)
        ctlText = String(format: "%.0f", workout.userEnteredCTL ?? currentCTL)
        atlText = String(format: "%.0f", workout.userEnteredATL ?? currentATL)
        tsbText = String(format: "%.0f", workout.userEnteredTSB ?? currentTSB)
    }

    private func confirmValues() {
        // User confirms calculated values match TP
        workout.calculatedTSS = workout.tss
        workout.tssVerificationStatus = .confirmed
        workout.verifiedAt = Date()

        // No user-entered values needed since they match
        workout.userEnteredTSS = nil
        workout.userEnteredCTL = nil
        workout.userEnteredATL = nil
        workout.userEnteredTSB = nil

        try? modelContext.save()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            showConfirmation = true
        }

        onVerified?(workout)

        // Trigger learning - confirmed means our calculation was correct
        Task {
            await triggerLearning(tssCorrect: true, delta: 0)
        }
    }

    private func saveCorrections() {
        // Save original calculated value for learning
        workout.calculatedTSS = workout.tss

        // Parse and save user-entered values
        if let tss = Double(tssText), abs(tss - workout.tss) > 0.5 {
            workout.userEnteredTSS = tss
            workout.tss = tss  // Update the actual TSS
        }

        if let ctl = Double(ctlText), abs(ctl - currentCTL) > 0.5 {
            workout.userEnteredCTL = ctl
        }

        if let atl = Double(atlText), abs(atl - currentATL) > 0.5 {
            workout.userEnteredATL = atl
        }

        if let tsb = Double(tsbText), abs(tsb - currentTSB) > 0.5 {
            workout.userEnteredTSB = tsb
        }

        workout.tssVerificationStatus = .corrected
        workout.verifiedAt = Date()

        try? modelContext.save()
        editingField = nil

        onVerified?(workout)

        // Trigger learning with the delta
        let delta = (workout.userEnteredTSS ?? workout.tss) - (workout.calculatedTSS ?? workout.tss)
        Task {
            await triggerLearning(tssCorrect: false, delta: delta)
        }
    }

    private func resetToEditing() {
        workout.tssVerificationStatus = .pending
        workout.verifiedAt = nil
        initializeTextFields()
        try? modelContext.save()
    }

    private func triggerLearning(tssCorrect: Bool, delta: Double) async {
        // This would integrate with TSSLearningEngine
        // For now, just log the learning event
        print("[QuickVerify] Learning event: correct=\(tssCorrect), delta=\(delta), category=\(workout.activityCategory.rawValue)")
    }
}

// MARK: - Compact Quick Verify (for workout cards)

struct CompactQuickVerify: View {
    @Bindable var workout: WorkoutRecord
    let currentCTL: Double
    let currentATL: Double

    @State private var showingFullVerify = false

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // TSS display
            VStack(alignment: .leading, spacing: 2) {
                Text("TSS")
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
                Text(String(format: "%.0f", workout.tss))
                    .font(AppFont.metricSmall)
                    .foregroundStyle(Color.textPrimary)
            }

            Spacer()

            // Status indicator and action
            switch workout.tssVerificationStatus {
            case .pending:
                Button {
                    showingFullVerify = true
                } label: {
                    Label("Verify", systemImage: "checkmark.circle")
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.accentPrimary)
                }
                .buttonStyle(.plain)

            case .confirmed:
                Label("Verified", systemImage: "checkmark.circle.fill")
                    .font(AppFont.captionLarge)
                    .foregroundStyle(Color.statusExcellent)

            case .corrected:
                HStack(spacing: Spacing.xxxs) {
                    if let userTSS = workout.userEnteredTSS,
                       let calcTSS = workout.calculatedTSS {
                        let delta = userTSS - calcTSS
                        Text(String(format: "%+.0f", delta))
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.accentPrimary)
                    }
                    Image(systemName: "pencil.circle.fill")
                        .foregroundStyle(Color.accentPrimary)
                }
                .font(AppFont.captionLarge)
            }
        }
        .sheet(isPresented: $showingFullVerify) {
            QuickVerifySheet(
                workout: workout,
                currentCTL: currentCTL,
                currentATL: currentATL,
                currentTSB: currentCTL - currentATL
            )
        }
    }
}

// MARK: - Quick Verify Sheet

struct QuickVerifySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var workout: WorkoutRecord
    let currentCTL: Double
    let currentATL: Double
    let currentTSB: Double

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Workout summary
                    workoutSummary

                    // Quick verify card
                    QuickVerifyCard(
                        workout: workout,
                        currentCTL: currentCTL,
                        currentATL: currentATL,
                        currentTSB: currentTSB
                    ) { _ in
                        dismiss()
                    }

                    // Instructions
                    instructionsView
                }
                .padding()
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("Verify TSS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private var workoutSummary: some View {
        HStack {
            Image(systemName: workout.activityIcon)
                .font(.title2)
                .foregroundStyle(Color.accentPrimary)

            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title ?? workout.activityCategory.rawValue)
                    .font(AppFont.titleMedium)
                Text("\(workout.dateFormatted) - \(workout.durationFormatted)")
                    .font(AppFont.captionLarge)
                    .foregroundStyle(Color.textSecondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    @ViewBuilder
    private var instructionsView: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Label("How to verify", systemImage: "info.circle")
                .font(AppFont.labelMedium)
                .foregroundStyle(Color.textSecondary)

            Text("1. Open TrainingPeaks and find this workout")
            Text("2. Check if the TSS and PMC values match")
            Text("3. Tap 'Matches TP' if they match, or edit the values if different")

            Text("This helps the app learn to calculate TSS more accurately for your activities.")
                .font(AppFont.captionLarge)
                .foregroundStyle(Color.textTertiary)
                .padding(.top, Spacing.xs)
        }
        .font(AppFont.bodySmall)
        .foregroundStyle(Color.textSecondary)
        .padding()
        .background(Color.backgroundSecondary)
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
    }
}

// MARK: - Preview

#Preview("Quick Verify Card") {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: WorkoutRecord.self, configurations: config)

    let workout = WorkoutRecord(
        activityType: "Cycling",
        activityCategory: .bike,
        title: "Morning Ride",
        startDate: Date(),
        endDate: Date().addingTimeInterval(3600),
        durationSeconds: 3600,
        distanceMeters: 30000,
        tss: 87,
        tssType: .power
    )
    container.mainContext.insert(workout)

    return QuickVerifyCard(
        workout: workout,
        currentCTL: 72,
        currentATL: 85,
        currentTSB: -13
    )
    .padding()
    .modelContainer(container)
}
