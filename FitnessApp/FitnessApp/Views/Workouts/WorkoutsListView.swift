import SwiftUI
import SwiftData

/// Full workout list view accessible from Performance tab
/// Provides search, filtering, and chronological grouping of all workouts
struct WorkoutsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\WorkoutRecord.startDate, order: .reverse)]) private var workouts: [WorkoutRecord]

    @State private var selectedFilter: ActivityCategory?
    @State private var selectedWorkout: WorkoutRecord?
    @State private var searchText = ""

    private var filteredWorkouts: [WorkoutRecord] {
        var result = workouts

        if let filter = selectedFilter {
            result = result.filter { $0.activityCategory == filter }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.title?.localizedCaseInsensitiveContains(searchText) ?? false ||
                $0.activityType.localizedCaseInsensitiveContains(searchText)
            }
        }

        return result
    }

    private var groupedWorkouts: [(key: String, workouts: [WorkoutRecord])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredWorkouts) { workout -> String in
            if calendar.isDateInToday(workout.startDate) {
                return "Today"
            } else if calendar.isDateInYesterday(workout.startDate) {
                return "Yesterday"
            } else if calendar.isDate(workout.startDate, equalTo: Date(), toGranularity: .weekOfYear) {
                return "This Week"
            } else if let lastWeek = calendar.date(byAdding: .weekOfYear, value: -1, to: Date()),
                      calendar.isDate(workout.startDate, equalTo: lastWeek, toGranularity: .weekOfYear) {
                return "Last Week"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "MMMM yyyy"
                return formatter.string(from: workout.startDate)
            }
        }

        // Sort by date (most recent first)
        let order = ["Today", "Yesterday", "This Week", "Last Week"]
        return grouped.sorted { lhs, rhs in
            let lhsIndex = order.firstIndex(of: lhs.key) ?? Int.max
            let rhsIndex = order.firstIndex(of: rhs.key) ?? Int.max
            if lhsIndex != rhsIndex {
                return lhsIndex < rhsIndex
            }
            // For month groups, sort by date
            return lhs.value.first?.startDate ?? Date() > rhs.value.first?.startDate ?? Date()
        }.map { (key: $0.key, workouts: $0.value) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter chips
            filterBar

            // Workout list
            if filteredWorkouts.isEmpty {
                emptyState
            } else {
                workoutList
            }
        }
        .background(Color.backgroundPrimary)
        .navigationTitle("All Workouts")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .searchable(text: $searchText, prompt: "Search workouts")
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailView(workout: workout)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Filter Bar

    @ViewBuilder
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                FilterChip(
                    title: "All",
                    isSelected: selectedFilter == nil,
                    action: { selectedFilter = nil }
                )

                ForEach(ActivityCategory.allCases, id: \.self) { category in
                    FilterChip(
                        title: category.rawValue,
                        icon: category.icon,
                        isSelected: selectedFilter == category,
                        color: category.themeColor,
                        action: { selectedFilter = category }
                    )
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
        }
        .background(Color.backgroundSecondary)
    }

    // MARK: - Workout List

    @ViewBuilder
    private var workoutList: some View {
        List {
            ForEach(groupedWorkouts, id: \.key) { group in
                Section(group.key) {
                    ForEach(group.workouts) { workout in
                        WorkoutListRow(workout: workout)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedWorkout = workout
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "figure.run")
                .font(.system(size: 60))
                .foregroundStyle(Color.textTertiary)

            Text("No Workouts")
                .font(AppFont.displaySmall)
                .foregroundStyle(Color.textPrimary)

            if searchText.isEmpty && selectedFilter == nil {
                Text("Your workouts from Apple Health will appear here.")
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("No workouts match your search criteria.")
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    searchText = ""
                    selectedFilter = nil
                } label: {
                    Text("Clear Filters")
                        .font(AppFont.labelMedium)
                        .foregroundStyle(Color.accentPrimary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WorkoutsListView()
    }
    .modelContainer(for: WorkoutRecord.self, inMemory: true)
}
