//
//  PMCCalculatorTests.swift
//  FitnessAppTests
//
//  Unit tests for Performance Management Chart calculations.
//

import XCTest
@testable import FitnessApp

final class PMCCalculatorTests: XCTestCase {

    // MARK: - CTL (Chronic Training Load) Tests

    func testCTL_NoTraining_DecaysTowardZero() {
        // With 0 TSS, CTL should decay toward zero
        let previousCTL = 50.0
        let newCTL = PMCCalculator.calculateCTL(previousCTL: previousCTL, todayTSS: 0)

        XCTAssertLessThan(newCTL, previousCTL)
        XCTAssertGreaterThan(newCTL, 0)
        // Decay should be approximately CTL * (1 - 1/42) = CTL * 0.976
        XCTAssertEqual(newCTL, previousCTL * (1 - 1/42), accuracy: 0.1)
    }

    func testCTL_TSS100_IncreasesFromZero() {
        // Starting from 0, 100 TSS should increase CTL
        let newCTL = PMCCalculator.calculateCTL(previousCTL: 0, todayTSS: 100)

        XCTAssertGreaterThan(newCTL, 0)
        // First day: 0 + (100 - 0) × (1/42) = 2.38
        XCTAssertEqual(newCTL, 100 / 42, accuracy: 0.1)
    }

    func testCTL_MaintainsFitness_WhenTSSEqualsCTL() {
        // When daily TSS equals current CTL, CTL should remain stable
        let currentCTL = 75.0
        let newCTL = PMCCalculator.calculateCTL(previousCTL: currentCTL, todayTSS: currentCTL)

        XCTAssertEqual(newCTL, currentCTL, accuracy: 0.01)
    }

    func testCTL_CustomTimeConstant() {
        // Test with custom time constant
        let previousCTL = 50.0
        let todayTSS = 100.0
        let customTimeConstant = 28.0  // 4 weeks instead of 6

        let newCTL = PMCCalculator.calculateCTL(
            previousCTL: previousCTL,
            todayTSS: todayTSS,
            timeConstant: customTimeConstant
        )

        // Decay should be faster with shorter time constant
        let defaultCTL = PMCCalculator.calculateCTL(previousCTL: previousCTL, todayTSS: todayTSS)
        XCTAssertGreaterThan(newCTL, defaultCTL)
    }

    // MARK: - ATL (Acute Training Load) Tests

    func testATL_RespondsFasterThanCTL() {
        // ATL should respond faster to training changes than CTL
        let previousValue = 50.0
        let todayTSS = 150.0

        let newCTL = PMCCalculator.calculateCTL(previousCTL: previousValue, todayTSS: todayTSS)
        let newATL = PMCCalculator.calculateATL(previousATL: previousValue, todayTSS: todayTSS)

        // ATL should change more due to shorter time constant (7 vs 42)
        let ctlChange = abs(newCTL - previousValue)
        let atlChange = abs(newATL - previousValue)

        XCTAssertGreaterThan(atlChange, ctlChange)
    }

    func testATL_DecaysFast_WithNoTraining() {
        // ATL should decay faster than CTL
        let previousATL = 100.0
        let newATL = PMCCalculator.calculateATL(previousATL: previousATL, todayTSS: 0)

        // Decay: ATL * (1 - 1/7) ≈ ATL * 0.857
        XCTAssertEqual(newATL, previousATL * (1 - 1/7), accuracy: 0.1)
    }

    func testATL_IncreasesQuickly_WithHighTSS() {
        // High TSS should significantly increase ATL
        let previousATL = 50.0
        let newATL = PMCCalculator.calculateATL(previousATL: previousATL, todayTSS: 200)

        // Change: (200 - 50) × (1/7) ≈ 21.4
        XCTAssertGreaterThan(newATL, previousATL + 20)
    }

    // MARK: - TSB (Training Stress Balance) Tests

    func testTSB_PositiveWhenFresh() {
        // TSB is positive when CTL > ATL (fresh/rested)
        let ctl = 75.0
        let atl = 50.0

        let tsb = PMCCalculator.calculateTSB(ctl: ctl, atl: atl)

        XCTAssertEqual(tsb, 25.0)
        XCTAssertGreaterThan(tsb, 0)
    }

    func testTSB_NegativeWhenFatigued() {
        // TSB is negative when ATL > CTL (fatigued)
        let ctl = 60.0
        let atl = 90.0

        let tsb = PMCCalculator.calculateTSB(ctl: ctl, atl: atl)

        XCTAssertEqual(tsb, -30.0)
        XCTAssertLessThan(tsb, 0)
    }

    func testTSB_ZeroWhenBalanced() {
        // TSB is zero when CTL equals ATL
        let value = 70.0

        let tsb = PMCCalculator.calculateTSB(ctl: value, atl: value)

        XCTAssertEqual(tsb, 0)
    }

    // MARK: - Integration Tests

    func testPMC_OneWeekOfConsistentTraining() {
        // Simulate one week of consistent training
        var ctl = 0.0
        var atl = 0.0
        let dailyTSS = 75.0

        for _ in 1...7 {
            ctl = PMCCalculator.calculateCTL(previousCTL: ctl, todayTSS: dailyTSS)
            atl = PMCCalculator.calculateATL(previousATL: atl, todayTSS: dailyTSS)
        }

        // After 7 days of 75 TSS:
        // CTL should be building slowly
        // ATL should be close to the daily TSS
        XCTAssertGreaterThan(ctl, 10)
        XCTAssertLessThan(ctl, 20)

        // ATL should be much closer to daily TSS due to faster response
        XCTAssertGreaterThan(atl, 50)
        XCTAssertLessThan(atl, 75)
    }

    func testPMC_RestAfterHardWeek() {
        // Build up fatigue then rest
        var ctl = 50.0
        var atl = 50.0

        // Hard week: 3 days of 150 TSS
        for _ in 1...3 {
            ctl = PMCCalculator.calculateCTL(previousCTL: ctl, todayTSS: 150)
            atl = PMCCalculator.calculateATL(previousATL: atl, todayTSS: 150)
        }

        let postHardATL = atl
        let postHardTSB = PMCCalculator.calculateTSB(ctl: ctl, atl: atl)

        // Should be fatigued (negative TSB)
        XCTAssertLessThan(postHardTSB, 0)

        // Rest for 3 days
        for _ in 1...3 {
            ctl = PMCCalculator.calculateCTL(previousCTL: ctl, todayTSS: 0)
            atl = PMCCalculator.calculateATL(previousATL: atl, todayTSS: 0)
        }

        let postRestTSB = PMCCalculator.calculateTSB(ctl: ctl, atl: atl)

        // ATL should drop significantly
        XCTAssertLessThan(atl, postHardATL)

        // TSB should improve (become less negative or positive)
        XCTAssertGreaterThan(postRestTSB, postHardTSB)
    }

    // MARK: - Constants Tests

    func testDefaultTimeConstants() {
        XCTAssertEqual(PMCCalculator.defaultCTLDays, 42)
        XCTAssertEqual(PMCCalculator.defaultATLDays, 7)
    }

    // MARK: - Edge Cases

    func testPMC_VeryHighTSS() {
        // Extreme TSS value
        let ctl = PMCCalculator.calculateCTL(previousCTL: 50, todayTSS: 500)
        let atl = PMCCalculator.calculateATL(previousATL: 50, todayTSS: 500)

        XCTAssertGreaterThan(ctl, 50)
        XCTAssertGreaterThan(atl, 50)
        // ATL change should be larger
        XCTAssertGreaterThan(atl - 50, ctl - 50)
    }

    func testPMC_ZeroPreviousValues() {
        let ctl = PMCCalculator.calculateCTL(previousCTL: 0, todayTSS: 0)
        let atl = PMCCalculator.calculateATL(previousATL: 0, todayTSS: 0)

        XCTAssertEqual(ctl, 0)
        XCTAssertEqual(atl, 0)
    }
}
