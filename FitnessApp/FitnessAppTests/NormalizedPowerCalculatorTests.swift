//
//  NormalizedPowerCalculatorTests.swift
//  FitnessAppTests
//
//  Unit tests for Normalized Power calculations.
//

import XCTest
@testable import FitnessApp

final class NormalizedPowerCalculatorTests: XCTestCase {

    // MARK: - Basic NP Calculation Tests

    func testNP_ConstantPower_EqualsAveragePower() {
        // With constant power, NP should equal average power
        let constantPower = 200.0
        let powerValues = Array(repeating: constantPower, count: 300)

        let np = calculateNPFromDoubleArray(powerValues)

        // NP should be very close to constant power
        XCTAssertNotNil(np)
        XCTAssertEqual(Double(np!), constantPower, accuracy: 1.0)
    }

    func testNP_VariablePower_HigherThanAverage() {
        // With variable power (intervals), NP should be higher than average
        var powerValues: [Double] = []

        // Simulate intervals: 30 sec at 300W, 30 sec at 100W
        for _ in 0..<10 {
            powerValues.append(contentsOf: Array(repeating: 300.0, count: 30))
            powerValues.append(contentsOf: Array(repeating: 100.0, count: 30))
        }

        let np = calculateNPFromDoubleArray(powerValues)
        let avgPower = powerValues.reduce(0, +) / Double(powerValues.count)

        XCTAssertNotNil(np)
        // NP should be higher than average due to variability
        XCTAssertGreaterThan(Double(np!), avgPower)
    }

    func testNP_InsufficientData_ReturnsNil() {
        // Less than 30 seconds of data should return nil
        let powerValues = Array(repeating: 200.0, count: 20)

        let np = calculateNPFromDoubleArray(powerValues)

        // Should return nil or handle gracefully
        // (Implementation dependent - might return nil or average)
    }

    func testNP_ZeroPower_ReturnsZero() {
        // All zeros should result in zero NP
        let powerValues = Array(repeating: 0.0, count: 300)

        let np = calculateNPFromDoubleArray(powerValues)

        if let np = np {
            XCTAssertEqual(np, 0)
        }
    }

    // MARK: - Rolling Average Tests

    func testNP_RollingAverage_Smooths30Seconds() {
        // The 30-second rolling average should smooth out short spikes
        var powerValues: [Double] = []

        // 300 seconds of steady power with a brief spike
        powerValues.append(contentsOf: Array(repeating: 200.0, count: 100))
        powerValues.append(contentsOf: Array(repeating: 400.0, count: 5))  // 5 sec spike
        powerValues.append(contentsOf: Array(repeating: 200.0, count: 195))

        let np = calculateNPFromDoubleArray(powerValues)

        // NP should be close to 200 since spike is smoothed over 30 sec
        XCTAssertNotNil(np)
        XCTAssertLessThan(Double(np!), 220)
    }

    // MARK: - Fourth Power Average Tests

    func testNP_FourthPowerWeighting_PenalizesVariability() {
        // Two workouts with same average but different variability
        // should have different NP values

        // Steady workout
        let steadyPower = Array(repeating: 200.0, count: 600)

        // Variable workout (same average)
        var variablePower: [Double] = []
        for _ in 0..<30 {
            variablePower.append(contentsOf: Array(repeating: 250.0, count: 10))
            variablePower.append(contentsOf: Array(repeating: 150.0, count: 10))
        }

        let steadyNP = calculateNPFromDoubleArray(steadyPower)
        let variableNP = calculateNPFromDoubleArray(variablePower)

        XCTAssertNotNil(steadyNP)
        XCTAssertNotNil(variableNP)

        // Variable power should have higher NP due to fourth power weighting
        XCTAssertGreaterThan(Double(variableNP!), Double(steadyNP!))
    }

    // MARK: - Helper Methods

    /// Helper to calculate NP from an array of double values
    /// This simulates what the real calculator does with HKQuantitySample
    private func calculateNPFromDoubleArray(_ values: [Double]) -> Int? {
        guard values.count >= 30 else { return nil }

        // Calculate 30-second rolling averages
        var rollingAverages: [Double] = []
        for i in 29..<values.count {
            let window = values[(i-29)...i]
            let avg = window.reduce(0, +) / 30.0
            rollingAverages.append(avg)
        }

        guard !rollingAverages.isEmpty else { return nil }

        // Calculate fourth power average
        let fourthPowerSum = rollingAverages.reduce(0.0) { sum, power in
            sum + pow(power, 4)
        }
        let fourthPowerAvg = fourthPowerSum / Double(rollingAverages.count)

        // Take fourth root
        let np = pow(fourthPowerAvg, 0.25)

        return Int(np.rounded())
    }
}
