import SwiftUI
import SwiftData

/// View showing workout history with filtering and details
struct WorkoutsView: View {
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
        NavigationStack {
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
            .navigationTitle("Workouts")
            .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search workouts")
            .sheet(item: $selectedWorkout) { workout in
                WorkoutDetailView(workout: workout)
            }
            .preferredColorScheme(.dark)
        }
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

            Text("Your workouts from Apple Health will appear here.")
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    var icon: String?
    let isSelected: Bool
    var color: Color = .accentPrimary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.xxs) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: IconSize.small))
                }
                Text(title)
                    .font(AppFont.labelMedium)
            }
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .background(isSelected ? color : Color.backgroundTertiary)
            .foregroundStyle(isSelected ? .white : Color.textSecondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(AppAnimation.springSnappy, value: isSelected)
    }
}

// MARK: - Workout List Row

struct WorkoutListRow: View {
    let workout: WorkoutRecord

    var body: some View {
        HStack(spacing: Spacing.sm) {
            // Activity icon with colored background
            Image(systemName: workout.activityIcon)
                .font(.system(size: IconSize.large))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(workout.activityCategory.themeColor)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))

            // Main info
            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(workout.title ?? workout.activityType)
                    .font(AppFont.bodyLarge)
                    .fontWeight(.medium)
                    .foregroundStyle(Color.textPrimary)

                HStack(spacing: Spacing.xs) {
                    Label(workout.durationFormatted, systemImage: "clock")
                    if let distance = workout.distanceFormatted {
                        Label(distance, systemImage: "arrow.left.arrow.right")
                    }
                }
                .font(AppFont.captionLarge)
                .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            // TSS and time
            VStack(alignment: .trailing, spacing: Spacing.xxxs) {
                HStack(spacing: Spacing.xxs) {
                    Text(String(format: "%.0f", workout.tss))
                        .font(AppFont.metricSmall)
                        .foregroundStyle(Color.textPrimary)
                    Text("TSS")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }

                Text(workout.timeFormatted)
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
            }
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Preview

#Preview {
    WorkoutsView()
        .modelContainer(for: WorkoutRecord.self, inMemory: true)
}
