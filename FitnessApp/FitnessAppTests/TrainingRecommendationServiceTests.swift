//
//  TrainingRecommendationServiceTests.swift
//  FitnessAppTests
//
//  Unit tests for training recommendation logic.
//

import XCTest
@testable import FitnessApp

final class TrainingRecommendationServiceTests: XCTestCase {

    // MARK: - Recommendation Generation Tests

    func testRecommendation_FullyReady_SuggestsQualitySession() {
        let recommendation = TrainingRecommendationService.generateRecommendation(
            for: .fullyReady,
            hasMetrics: true
        )

        XCTAssertTrue(recommendation.contains("quality") || recommendation.contains("high-intensity"))
    }

    func testRecommendation_MostlyReady_SuggestsNormalTraining() {
        let recommendation = TrainingRecommendationService.generateRecommendation(
            for: .mostlyReady,
            hasMetrics: true
        )

        XCTAssertTrue(recommendation.contains("Normal") || recommendation.contains("appropriate"))
    }

    func testRecommendation_ReducedCapacity_SuggestsEasierSession() {
        let recommendation = TrainingRecommendationService.generateRecommendation(
            for: .reducedCapacity,
            hasMetrics: true
        )

        XCTAssertTrue(recommendation.contains("easier") || recommendation.contains("recovery"))
    }

    func testRecommendation_RestRecommended_SuggestsRest() {
        let recommendation = TrainingRecommendationService.generateRecommendation(
            for: .restRecommended,
            hasMetrics: true
        )

        XCTAssertTrue(recommendation.contains("rest") || recommendation.contains("day off"))
    }

    func testRecommendation_NoMetrics_ReturnsNoDataMessage() {
        let recommendation = TrainingRecommendationService.generateRecommendation(
            for: .fullyReady,
            hasMetrics: false
        )

        XCTAssertTrue(recommendation.contains("No data") || recommendation.contains("first workout"))
    }

    // MARK: - Workout Suggestion Tests

    func testWorkoutSuggestion_FullyReady_ReturnsIntensiveWorkout() {
        let suggestion = TrainingRecommendationService.suggestWorkout(
            for: .fullyReady,
            hasMetrics: true
        )

        XCTAssertNotNil(suggestion)
        XCTAssertTrue(suggestion?.contains("interval") == true || suggestion?.contains("hard") == true)
    }

    func testWorkoutSuggestion_MostlyReady_ReturnsModerateWorkout() {
        let suggestion = TrainingRecommendationService.suggestWorkout(
            for: .mostlyReady,
            hasMetrics: true
        )

        XCTAssertNotNil(suggestion)
        XCTAssertTrue(suggestion?.contains("Moderate") == true || suggestion?.contains("endurance") == true)
    }

    func testWorkoutSuggestion_ReducedCapacity_ReturnsEasyWorkout() {
        let suggestion = TrainingRecommendationService.suggestWorkout(
            for: .reducedCapacity,
            hasMetrics: true
        )

        XCTAssertNotNil(suggestion)
        XCTAssertTrue(suggestion?.lowercased().contains("easy") == true || suggestion?.lowercased().contains("recovery") == true)
    }

    func testWorkoutSuggestion_RestRecommended_ReturnsRestOrYoga() {
        let suggestion = TrainingRecommendationService.suggestWorkout(
            for: .restRecommended,
            hasMetrics: true
        )

        XCTAssertNotNil(suggestion)
        XCTAssertTrue(suggestion?.lowercased().contains("rest") == true || suggestion?.lowercased().contains("yoga") == true)
    }

    func testWorkoutSuggestion_NoMetrics_ReturnsNil() {
        let suggestion = TrainingRecommendationService.suggestWorkout(
            for: .fullyReady,
            hasMetrics: false
        )

        XCTAssertNil(suggestion)
    }

    // MARK: - Baseline Calculation Tests

    func testCalculateBaseline_WithValues_ReturnsAverage() {
        let values = [10.0, 20.0, 30.0, 40.0, 50.0]
        let baseline = TrainingRecommendationService.calculateBaseline(from: values)

        XCTAssertNotNil(baseline)
        XCTAssertEqual(baseline!, 30.0, accuracy: 0.01)
    }

    func testCalculateBaseline_EmptyArray_ReturnsNil() {
        let baseline = TrainingRecommendationService.calculateBaseline(from: [])

        XCTAssertNil(baseline)
    }

    func testCalculateBaseline_SingleValue_ReturnsThatValue() {
        let baseline = TrainingRecommendationService.calculateBaseline(from: [42.0])

        XCTAssertNotNil(baseline)
        XCTAssertEqual(baseline!, 42.0, accuracy: 0.01)
    }

    // MARK: - Date Range Helper Tests

    func testDaysAgo_ReturnsCorrectDate() {
        let today = Date()
        let sevenDaysAgo = TrainingRecommendationService.daysAgo(7)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.day], from: sevenDaysAgo, to: today)

        XCTAssertEqual(components.day, 7)
    }

    func testDaysAgo_ZeroDays_ReturnsToday() {
        let today = Calendar.current.startOfDay(for: Date())
        let result = Calendar.current.startOfDay(for: TrainingRecommendationService.daysAgo(0))

        XCTAssertEqual(result, today)
    }

    // MARK: - All Readiness Levels Coverage

    func testAllReadinessLevels_ProduceUniqueRecommendations() {
        let readinessLevels: [TrainingReadiness] = [
            .fullyReady,
            .mostlyReady,
            .reducedCapacity,
            .restRecommended
        ]

        var recommendations: Set<String> = []

        for level in readinessLevels {
            let recommendation = TrainingRecommendationService.generateRecommendation(
                for: level,
                hasMetrics: true
            )
            recommendations.insert(recommendation)
        }

        // Each readiness level should produce a unique recommendation
        XCTAssertEqual(recommendations.count, readinessLevels.count)
    }

    func testAllReadinessLevels_ProduceUniqueSuggestions() {
        let readinessLevels: [TrainingReadiness] = [
            .fullyReady,
            .mostlyReady,
            .reducedCapacity,
            .restRecommended
        ]

        var suggestions: Set<String> = []

        for level in readinessLevels {
            if let suggestion = TrainingRecommendationService.suggestWorkout(
                for: level,
                hasMetrics: true
            ) {
                suggestions.insert(suggestion)
            }
        }

        // Each readiness level should produce a unique suggestion
        XCTAssertEqual(suggestions.count, readinessLevels.count)
    }
}
