//
//  TSSCalculatorTests.swift
//  FitnessAppTests
//
//  Unit tests for Training Stress Score calculations.
//

import XCTest
@testable import FitnessApp

final class TSSCalculatorTests: XCTestCase {

    // MARK: - Power-Based TSS Tests

    func testPowerTSS_OneHourAtFTP_Returns100() {
        // One hour at FTP should equal exactly 100 TSS
        let result = TSSCalculator.calculatePowerTSS(
            normalizedPower: 250,
            durationSeconds: 3600,
            ftp: 250
        )

        XCTAssertEqual(result.tss, 100, accuracy: 0.1)
        XCTAssertEqual(result.intensityFactor, 1.0, accuracy: 0.01)
        XCTAssertEqual(result.type, .power)
    }

    func testPowerTSS_HalfHourAtFTP_Returns50() {
        // 30 minutes at FTP should equal 50 TSS
        let result = TSSCalculator.calculatePowerTSS(
            normalizedPower: 250,
            durationSeconds: 1800,
            ftp: 250
        )

        XCTAssertEqual(result.tss, 50, accuracy: 0.1)
    }

    func testPowerTSS_OneHourAt90Percent_ReturnsApprox81() {
        // 1 hour at 90% FTP: IF=0.9, TSS = (3600 × 225 × 0.9) / (250 × 3600) × 100 = 81
        let result = TSSCalculator.calculatePowerTSS(
            normalizedPower: 225,  // 90% of 250
            durationSeconds: 3600,
            ftp: 250
        )

        XCTAssertEqual(result.tss, 81, accuracy: 0.5)
        XCTAssertEqual(result.intensityFactor, 0.9, accuracy: 0.01)
    }

    func testPowerTSS_ZeroFTP_ReturnsZero() {
        let result = TSSCalculator.calculatePowerTSS(
            normalizedPower: 200,
            durationSeconds: 3600,
            ftp: 0
        )

        XCTAssertEqual(result.tss, 0)
    }

    func testPowerTSS_ZeroDuration_ReturnsZero() {
        let result = TSSCalculator.calculatePowerTSS(
            normalizedPower: 200,
            durationSeconds: 0,
            ftp: 250
        )

        XCTAssertEqual(result.tss, 0)
    }

    func testPowerTSS_HighIntensity_ReturnsExpectedValue() {
        // 1 hour at 110% FTP: IF=1.1, TSS should be ~121
        let result = TSSCalculator.calculatePowerTSS(
            normalizedPower: 275,  // 110% of 250
            durationSeconds: 3600,
            ftp: 250
        )

        XCTAssertEqual(result.tss, 121, accuracy: 1)
        XCTAssertEqual(result.intensityFactor, 1.1, accuracy: 0.01)
    }

    // MARK: - Running TSS Tests

    func testRunningTSS_OneHourAtThreshold_Returns100() {
        // 1 hour at threshold pace should equal ~100 TSS
        let thresholdPace = 270.0  // 4:30/km in seconds
        let result = TSSCalculator.calculateRunningTSS(
            normalizedGradedPace: thresholdPace,
            durationSeconds: 3600,
            thresholdPace: thresholdPace
        )

        XCTAssertEqual(result.tss, 100, accuracy: 0.5)
        XCTAssertEqual(result.intensityFactor, 1.0, accuracy: 0.01)
    }

    func testRunningTSS_SlowerPace_ReturnsLowerTSS() {
        // Running at 5:00/km when threshold is 4:30/km
        let result = TSSCalculator.calculateRunningTSS(
            normalizedGradedPace: 300.0,  // 5:00/km
            durationSeconds: 3600,
            thresholdPace: 270.0  // 4:30/km
        )

        // IF = 270/300 = 0.9, TSS = 1 × 0.81 × 100 = 81
        XCTAssertEqual(result.tss, 81, accuracy: 1)
        XCTAssertLessThan(result.intensityFactor, 1.0)
    }

    func testRunningTSS_FasterPace_ReturnsHigherTSS() {
        // Running at 4:00/km when threshold is 4:30/km
        let result = TSSCalculator.calculateRunningTSS(
            normalizedGradedPace: 240.0,  // 4:00/km
            durationSeconds: 3600,
            thresholdPace: 270.0  // 4:30/km
        )

        XCTAssertGreaterThan(result.tss, 100)
        XCTAssertGreaterThan(result.intensityFactor, 1.0)
    }

    func testRunningTSS_ZeroThreshold_ReturnsZero() {
        let result = TSSCalculator.calculateRunningTSS(
            normalizedGradedPace: 300.0,
            durationSeconds: 3600,
            thresholdPace: 0
        )

        XCTAssertEqual(result.tss, 0)
    }

    // MARK: - Heart Rate TSS Tests

    func testHeartRateTSS_OneHourAtLTHR_Returns100() {
        // 1 hour at LTHR should be approximately 100 TSS
        let result = TSSCalculator.calculateHeartRateTSS(
            averageHeartRate: 165,
            durationSeconds: 3600,
            lthr: 165,
            maxHR: 190
        )

        // hrTSS uses TRIMP-based formula, so exact value varies
        XCTAssertGreaterThan(result.tss, 80)
        XCTAssertLessThan(result.tss, 120)
    }

    func testHeartRateTSS_ZoneTwoEffort_ReturnsModerateValue() {
        // Zone 2 (70-80% LTHR) should return lower TSS
        let result = TSSCalculator.calculateHeartRateTSS(
            averageHeartRate: 130,  // ~78% of 165
            durationSeconds: 3600,
            lthr: 165,
            maxHR: 190
        )

        XCTAssertLessThan(result.tss, 80)
        XCTAssertGreaterThan(result.tss, 30)
    }

    // MARK: - Swimming TSS Tests

    func testSwimmingTSS_OneHourAtThreshold_ReturnsExpectedValue() {
        // 1 hour of swimming at threshold pace
        let result = TSSCalculator.calculateSwimmingTSS(
            averagePace: 90.0,  // 1:30/100m
            durationSeconds: 3600,
            thresholdPace: 90.0  // 1:30/100m
        )

        XCTAssertGreaterThan(result.tss, 80)
        XCTAssertLessThan(result.tss, 120)
    }

    // MARK: - TSSResult Tests

    func testTSSResult_TypeDescription() {
        let powerResult = TSSResult(tss: 100, type: .power, intensityFactor: 1.0)
        let paceResult = TSSResult(tss: 100, type: .pace, intensityFactor: 1.0)
        let hrResult = TSSResult(tss: 100, type: .heartRate, intensityFactor: 1.0)

        XCTAssertEqual(powerResult.type, .power)
        XCTAssertEqual(paceResult.type, .pace)
        XCTAssertEqual(hrResult.type, .heartRate)
    }

    // MARK: - Edge Cases

    func testPowerTSS_VeryShortDuration_ReturnsLowValue() {
        // 5 minute workout
        let result = TSSCalculator.calculatePowerTSS(
            normalizedPower: 300,
            durationSeconds: 300,
            ftp: 250
        )

        XCTAssertLessThan(result.tss, 20)
    }

    func testPowerTSS_VeryLongDuration_ReturnsHighValue() {
        // 4 hour ride at moderate intensity
        let result = TSSCalculator.calculatePowerTSS(
            normalizedPower: 175,  // 70% of 250
            durationSeconds: 14400,  // 4 hours
            ftp: 250
        )

        XCTAssertGreaterThan(result.tss, 150)
    }
}
