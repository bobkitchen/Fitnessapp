//
//  TSSAccuracyCard.swift
//  FitnessApp
//
//  Dashboard card showing TSS calculation accuracy and learning progress.
//  Displays per-activity accuracy, trends, and recent verifications.
//

import SwiftUI
import SwiftData
import Charts

// MARK: - TSS Accuracy Card

struct TSSAccuracyCard: View {
    @Environment(\.modelContext) private var modelContext
    @State private var accuracyStats: TSSAccuracyStats?
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            // Header with overall accuracy
            header

            if isExpanded {
                // Per-activity breakdown
                activityBreakdown

                Divider()
                    .background(Color.borderPrimary)

                // Recent verifications
                recentVerifications

                // Accuracy trend chart
                if let stats = accuracyStats, stats.trendData.count >= 3 {
                    accuracyTrendChart(data: stats.trendData)
                }
            }
        }
        .padding(Spacing.md)
        .cardBackground(cornerRadius: CornerRadius.large)
        .onTapGesture {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }
        .onAppear {
            loadAccuracyStats()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("TSS Accuracy")
        .accessibilityHint(isExpanded ? "Tap to collapse" : "Tap to expand for details")
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("TSS Accuracy")
                    .font(AppFont.labelMedium)
                    .foregroundStyle(Color.textSecondary)

                if let stats = accuracyStats {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                        Text(String(format: "%.0f%%", stats.overallAccuracy))
                            .font(AppFont.metricMedium)
                            .foregroundStyle(accuracyColor(stats.overallAccuracy))

                        if stats.totalVerified > 0 {
                            Text("(\(stats.totalVerified) verified)")
                                .font(AppFont.captionSmall)
                                .foregroundStyle(Color.textTertiary)
                        }
                    }
                } else {
                    Text("--")
                        .font(AppFont.metricMedium)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            // Pending count badge
            if let stats = accuracyStats, stats.pendingCount > 0 {
                HStack(spacing: Spacing.xxs) {
                    Text("\(stats.pendingCount)")
                        .font(AppFont.labelLarge)
                        .foregroundStyle(Color.textPrimary)
                    Text("pending")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }
                .padding(.horizontal, Spacing.sm)
                .padding(.vertical, Spacing.xxs)
                .background(Color.accentPrimary.opacity(0.2))
                .clipShape(Capsule())
            }

            // Expand indicator
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
    }

    // MARK: - Activity Breakdown

    @ViewBuilder
    private var activityBreakdown: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("By Activity")
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)

            if let stats = accuracyStats {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: Spacing.sm) {
                    ForEach(stats.categoryStats, id: \.category) { catStat in
                        ActivityAccuracyRow(stat: catStat)
                    }
                }
            }
        }
    }

    // MARK: - Recent Verifications

    @ViewBuilder
    private var recentVerifications: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Recent Verifications")
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)

            if let stats = accuracyStats, !stats.recentVerifications.isEmpty {
                ForEach(stats.recentVerifications.prefix(3), id: \.id) { verification in
                    RecentVerificationRow(verification: verification)
                }
            } else {
                Text("No verifications yet")
                    .font(AppFont.captionLarge)
                    .foregroundStyle(Color.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, Spacing.sm)
            }
        }
    }

    // MARK: - Accuracy Trend Chart

    @ViewBuilder
    private func accuracyTrendChart(data: [TSSAccuracyTrendPoint]) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Accuracy Trend")
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)

            Chart(data) { point in
                LineMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Accuracy", point.accuracy)
                )
                .foregroundStyle(Color.accentPrimary)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Week", point.weekStart),
                    y: .value("Accuracy", point.accuracy)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.accentPrimary.opacity(0.3), Color.accentPrimary.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { value in
                    AxisValueLabel {
                        Text("\(value.as(Int.self) ?? 0)%")
                            .font(AppFont.captionSmall)
                            .foregroundStyle(Color.textTertiary)
                    }
                    AxisGridLine()
                        .foregroundStyle(Color.borderPrimary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }
            }
            .frame(height: Layout.chartHeightCompact)
        }
    }

    // MARK: - Helpers

    private func accuracyColor(_ accuracy: Double) -> Color {
        switch accuracy {
        case 95...: return .statusOptimal
        case 85..<95: return .accentPrimary
        case 70..<85: return .statusModerate
        default: return .statusLow
        }
    }

    private func loadAccuracyStats() {
        Task { @MainActor in
            accuracyStats = calculateAccuracyStats()
        }
    }

    private func calculateAccuracyStats() -> TSSAccuracyStats {
        // Fetch all verified workouts
        let verifiedPredicate = #Predicate<WorkoutRecord> { workout in
            workout.tssVerificationStatusRaw != nil &&
            workout.tssVerificationStatusRaw != "pending"
        }
        let verifiedDescriptor = FetchDescriptor<WorkoutRecord>(
            predicate: verifiedPredicate,
            sortBy: [SortDescriptor(\.verifiedAt, order: .reverse)]
        )

        let verifiedWorkouts = (try? modelContext.fetch(verifiedDescriptor)) ?? []

        // Fetch pending workouts
        let pendingPredicate = #Predicate<WorkoutRecord> { workout in
            workout.tssVerificationStatusRaw == nil ||
            workout.tssVerificationStatusRaw == "pending"
        }
        let pendingDescriptor = FetchDescriptor<WorkoutRecord>(predicate: pendingPredicate)
        let pendingCount = (try? modelContext.fetchCount(pendingDescriptor)) ?? 0

        // Calculate overall accuracy
        var totalError: Double = 0
        var errorCount = 0

        for workout in verifiedWorkouts {
            if let calculated = workout.calculatedTSS,
               let userEntered = workout.userEnteredTSS {
                let error = abs(calculated - userEntered) / max(userEntered, 1) * 100
                totalError += min(error, 100)  // Cap at 100% error
                errorCount += 1
            }
        }

        let confirmedCount = verifiedWorkouts.filter { $0.tssVerificationStatus == .confirmed }.count
        let correctedCount = verifiedWorkouts.filter { $0.tssVerificationStatus == .corrected }.count

        // Overall accuracy: confirmed workouts are 100% accurate, corrected have some error
        let overallAccuracy: Double
        if verifiedWorkouts.isEmpty {
            overallAccuracy = 0
        } else if errorCount == 0 {
            overallAccuracy = 100  // All confirmed
        } else {
            let avgError = totalError / Double(errorCount)
            let correctedAccuracy = max(0, 100 - avgError)
            // Weight by count: confirmed = 100%, corrected = calculated accuracy
            let totalWeight = Double(confirmedCount) + Double(correctedCount)
            overallAccuracy = (Double(confirmedCount) * 100 + Double(correctedCount) * correctedAccuracy) / max(totalWeight, 1)
        }

        // Per-category stats
        let categoryStats = ActivityCategory.allCases.compactMap { category -> CategoryAccuracyStat? in
            let categoryWorkouts = verifiedWorkouts.filter { $0.activityCategory == category }
            guard !categoryWorkouts.isEmpty else { return nil }

            let confirmed = categoryWorkouts.filter { $0.tssVerificationStatus == .confirmed }.count
            let corrected = categoryWorkouts.filter { $0.tssVerificationStatus == .corrected }.count

            var catError: Double = 0
            var catErrorCount = 0

            for workout in categoryWorkouts {
                if let calculated = workout.calculatedTSS,
                   let userEntered = workout.userEnteredTSS {
                    let error = abs(calculated - userEntered) / max(userEntered, 1) * 100
                    catError += min(error, 100)
                    catErrorCount += 1
                }
            }

            let accuracy: Double
            if catErrorCount == 0 {
                accuracy = 100
            } else {
                let avgError = catError / Double(catErrorCount)
                let correctedAccuracy = max(0, 100 - avgError)
                let totalWeight = Double(confirmed) + Double(corrected)
                accuracy = (Double(confirmed) * 100 + Double(corrected) * correctedAccuracy) / max(totalWeight, 1)
            }

            return CategoryAccuracyStat(
                category: category,
                accuracy: accuracy,
                sampleCount: categoryWorkouts.count
            )
        }

        // Recent verifications
        let recentVerifications = verifiedWorkouts.prefix(5).map { workout in
            RecentVerification(
                id: workout.id,
                activityType: workout.activityType,
                category: workout.activityCategory,
                date: workout.verifiedAt ?? workout.startDate,
                status: workout.tssVerificationStatus,
                delta: workout.userEnteredTSS.map { $0 - (workout.calculatedTSS ?? workout.tss) }
            )
        }

        // Trend data (weekly accuracy over last 8 weeks)
        let calendar = Calendar.current
        var trendData: [TSSAccuracyTrendPoint] = []

        for weeksAgo in (0..<8).reversed() {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: Date()) else { continue }
            let weekEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) ?? weekStart

            let weekWorkouts = verifiedWorkouts.filter { workout in
                guard let verifiedAt = workout.verifiedAt else { return false }
                return verifiedAt >= weekStart && verifiedAt < weekEnd
            }

            guard !weekWorkouts.isEmpty else { continue }

            let weekConfirmed = weekWorkouts.filter { $0.tssVerificationStatus == .confirmed }.count
            let weekCorrected = weekWorkouts.filter { $0.tssVerificationStatus == .corrected }.count

            var weekError: Double = 0
            var weekErrorCount = 0

            for workout in weekWorkouts {
                if let calculated = workout.calculatedTSS,
                   let userEntered = workout.userEnteredTSS {
                    let error = abs(calculated - userEntered) / max(userEntered, 1) * 100
                    weekError += min(error, 100)
                    weekErrorCount += 1
                }
            }

            let weekAccuracy: Double
            if weekErrorCount == 0 {
                weekAccuracy = 100
            } else {
                let avgError = weekError / Double(weekErrorCount)
                let correctedAccuracy = max(0, 100 - avgError)
                let totalWeight = Double(weekConfirmed) + Double(weekCorrected)
                weekAccuracy = (Double(weekConfirmed) * 100 + Double(weekCorrected) * correctedAccuracy) / max(totalWeight, 1)
            }

            trendData.append(TSSAccuracyTrendPoint(
                weekStart: weekStart,
                accuracy: weekAccuracy,
                sampleCount: weekWorkouts.count
            ))
        }

        return TSSAccuracyStats(
            overallAccuracy: overallAccuracy,
            totalVerified: verifiedWorkouts.count,
            confirmedCount: confirmedCount,
            correctedCount: correctedCount,
            pendingCount: pendingCount,
            categoryStats: categoryStats,
            recentVerifications: Array(recentVerifications),
            trendData: trendData
        )
    }
}

// MARK: - Activity Accuracy Row

private struct ActivityAccuracyRow: View {
    let stat: CategoryAccuracyStat

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: stat.category.icon)
                .font(.caption)
                .foregroundStyle(stat.category.themeColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.category.rawValue)
                    .font(AppFont.captionLarge)
                    .foregroundStyle(Color.textSecondary)

                HStack(spacing: Spacing.xxs) {
                    Text(String(format: "%.0f%%", stat.accuracy))
                        .font(AppFont.labelLarge)
                        .foregroundStyle(accuracyColor(stat.accuracy))

                    Text("(\(stat.sampleCount))")
                        .font(AppFont.captionSmall)
                        .foregroundStyle(Color.textTertiary)
                }
            }

            Spacer()

            // Mini progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.backgroundTertiary)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(accuracyColor(stat.accuracy))
                        .frame(width: geo.size.width * (stat.accuracy / 100))
                }
            }
            .frame(width: 40, height: 6)
        }
        .padding(Spacing.xs)
        .background(Color.backgroundTertiary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
    }

    private func accuracyColor(_ accuracy: Double) -> Color {
        switch accuracy {
        case 95...: return .statusOptimal
        case 85..<95: return .accentPrimary
        case 70..<85: return .statusModerate
        default: return .statusLow
        }
    }
}

// MARK: - Recent Verification Row

private struct RecentVerificationRow: View {
    let verification: RecentVerification

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: verification.category.icon)
                .font(.caption)
                .foregroundStyle(verification.category.themeColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(verification.activityType)
                    .font(AppFont.captionLarge)
                    .foregroundStyle(Color.textSecondary)

                Text(verification.date, style: .relative)
                    .font(AppFont.captionSmall)
                    .foregroundStyle(Color.textTertiary)
            }

            Spacer()

            // Status
            HStack(spacing: Spacing.xxs) {
                Image(systemName: verification.status.icon)
                    .font(.caption)

                if let delta = verification.delta, verification.status == .corrected {
                    Text(String(format: "%+.0f", delta))
                        .font(AppFont.captionSmall)
                }
            }
            .foregroundStyle(verification.status == .confirmed ? Color.statusOptimal : Color.accentPrimary)
        }
        .padding(.vertical, Spacing.xxs)
    }
}

// MARK: - Data Models

struct TSSAccuracyStats {
    let overallAccuracy: Double
    let totalVerified: Int
    let confirmedCount: Int
    let correctedCount: Int
    let pendingCount: Int
    let categoryStats: [CategoryAccuracyStat]
    let recentVerifications: [RecentVerification]
    let trendData: [TSSAccuracyTrendPoint]
}

struct CategoryAccuracyStat {
    let category: ActivityCategory
    let accuracy: Double
    let sampleCount: Int
}

struct RecentVerification: Identifiable {
    let id: UUID
    let activityType: String
    let category: ActivityCategory
    let date: Date
    let status: TSSVerificationStatus
    let delta: Double?
}

struct TSSAccuracyTrendPoint: Identifiable {
    var id: Date { weekStart }
    let weekStart: Date
    let accuracy: Double
    let sampleCount: Int
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack {
            TSSAccuracyCard()
                .padding()
        }
    }
    .background(Color.backgroundPrimary)
    .modelContainer(for: WorkoutRecord.self, inMemory: true)
}
