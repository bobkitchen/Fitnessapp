import SwiftUI
import SwiftData

/// Form-based edit view for modifying workout properties and deleting workouts
struct WorkoutEditView: View {
    @Bindable var workout: WorkoutRecord
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            detailsSection
            trainingLoadSection
            metricsSection
            notesSection
            deleteSection
        }
        .navigationTitle("Edit Workout")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete Workout?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { deleteWorkout() }
        } message: {
            Text("This workout will be permanently removed from your training log.")
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: optionalStringBinding(\.title))

            Picker("Activity Type", selection: activityCategoryBinding) {
                ForEach(ActivityCategory.allCases, id: \.self) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .tag(category)
                }
            }

            Toggle("Indoor Workout", isOn: $workout.indoorWorkout)
        }
    }

    @ViewBuilder
    private var trainingLoadSection: some View {
        Section("Training Load") {
            HStack {
                Text("TSS")
                Spacer()
                TextField("0", value: $workout.tss, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            HStack {
                Text("Intensity Factor")
                Spacer()
                TextField("0.00", value: $workout.intensityFactor, format: .number)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
            }

            Picker("RPE", selection: optionalIntPickerBinding(\.rpe)) {
                Text("None").tag(Optional<Int>.none)
                ForEach(1...10, id: \.self) { value in
                    Text("\(value)").tag(Optional(value))
                }
            }
        }
    }

    @ViewBuilder
    private var metricsSection: some View {
        Section("Metrics") {
            numericRow("Avg Heart Rate", binding: optionalIntBinding(\.averageHeartRate), unit: "bpm")
            numericRow("Max Heart Rate", binding: optionalIntBinding(\.maxHeartRate), unit: "bpm")
            numericRow("Avg Power", binding: optionalIntBinding(\.averagePower), unit: "W")
            numericRow("Normalized Power", binding: optionalIntBinding(\.normalizedPower), unit: "W")
            numericRow("Avg Cadence", binding: optionalIntBinding(\.averageCadence), unit: workout.activityCategory == .bike ? "rpm" : "spm")
            numericRow("Calories", binding: optionalDoubleBinding(\.activeCalories), unit: "kcal")
        }
    }

    @ViewBuilder
    private var notesSection: some View {
        Section("Notes") {
            VStack(alignment: .leading) {
                Text("Notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: optionalStringBinding(\.notes))
                    .frame(minHeight: 80)
            }

            VStack(alignment: .leading) {
                Text("Coach Comments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: optionalStringBinding(\.coachComments))
                    .frame(minHeight: 80)
            }
        }
    }

    @ViewBuilder
    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    Text("Delete Workout")
                    Spacer()
                }
            }
        }
    }

    // MARK: - Bindings

    private var activityCategoryBinding: Binding<ActivityCategory> {
        Binding(
            get: { workout.activityCategory },
            set: { workout.activityCategory = $0 }
        )
    }

    private func optionalStringBinding(_ keyPath: ReferenceWritableKeyPath<WorkoutRecord, String?>) -> Binding<String> {
        Binding<String>(
            get: { workout[keyPath: keyPath] ?? "" },
            set: { workout[keyPath: keyPath] = $0.isEmpty ? nil : $0 }
        )
    }

    private func optionalIntBinding(_ keyPath: ReferenceWritableKeyPath<WorkoutRecord, Int?>) -> Binding<String> {
        Binding<String>(
            get: { workout[keyPath: keyPath].map { String($0) } ?? "" },
            set: { workout[keyPath: keyPath] = Int($0) }
        )
    }

    private func optionalDoubleBinding(_ keyPath: ReferenceWritableKeyPath<WorkoutRecord, Double?>) -> Binding<String> {
        Binding<String>(
            get: { workout[keyPath: keyPath].map { String($0) } ?? "" },
            set: { workout[keyPath: keyPath] = Double($0) }
        )
    }

    private func optionalIntPickerBinding(_ keyPath: ReferenceWritableKeyPath<WorkoutRecord, Int?>) -> Binding<Int?> {
        Binding<Int?>(
            get: { workout[keyPath: keyPath] },
            set: { workout[keyPath: keyPath] = $0 }
        )
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func numericRow(_ label: String, binding: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("—", text: binding)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func deleteWorkout() {
        modelContext.delete(workout)
        try? modelContext.save()
        dismiss()
    }
}
