//
//  HealthKitProfileService.swift
//  FitnessApp
//
//  Handles profile data from HealthKit: age, height, weight,
//  biological sex, and body composition.
//

import Foundation
import HealthKit

/// Service for fetching profile and body data from HealthKit.
final class HealthKitProfileService {

    private let core: HealthKitCore

    init(core: HealthKitCore = .shared) {
        self.core = core
    }

    // MARK: - Characteristics (Sync)

    /// Fetch date of birth from HealthKit characteristics
    func fetchDateOfBirth() throws -> Date? {
        let dobComponents = try core.healthStore.dateOfBirthComponents()
        return Calendar.current.date(from: dobComponents)
    }

    /// Calculate age from date of birth
    func fetchAge() throws -> Int? {
        guard let dob = try fetchDateOfBirth() else { return nil }
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: dob, to: Date())
        return ageComponents.year
    }

    /// Fetch biological sex from HealthKit characteristics
    func fetchBiologicalSex() throws -> HKBiologicalSex? {
        let biologicalSex = try core.healthStore.biologicalSex()
        return biologicalSex.biologicalSex
    }

    // MARK: - Body Measurements (Async)

    /// Fetch most recent height measurement (in cm)
    func fetchHeight() async throws -> Double? {
        guard let heightType = HKQuantityType.quantityType(forIdentifier: .height) else {
            throw HealthKitError.typeNotAvailable
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: heightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let heightCm = sample.quantity.doubleValue(for: .meterUnit(with: .centi))
                continuation.resume(returning: heightCm)
            }

            core.healthStore.execute(query)
        }
    }

    /// Fetch most recent weight measurement (in kg)
    func fetchWeight() async throws -> Double? {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            throw HealthKitError.typeNotAvailable
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: weightType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let weightKg = sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
                continuation.resume(returning: weightKg)
            }

            core.healthStore.execute(query)
        }
    }

    /// Fetch body fat percentage
    func fetchBodyFatPercentage() async throws -> Double? {
        guard let bfType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage) else {
            throw HealthKitError.typeNotAvailable
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: bfType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sample = samples?.first as? HKQuantitySample else {
                    continuation.resume(returning: nil)
                    return
                }

                let percentage = sample.quantity.doubleValue(for: .percent()) * 100
                continuation.resume(returning: percentage)
            }

            core.healthStore.execute(query)
        }
    }

    // MARK: - Aggregated Profile Data

    /// Fetch all profile data at once
    func fetchProfileData() async throws -> HealthProfileData {
        // Fetch characteristics (sync)
        let age = try? fetchAge()
        let biologicalSex = try? fetchBiologicalSex()

        // Fetch measurements (async)
        let height = try? await fetchHeight()
        let weight = try? await fetchWeight()

        return HealthProfileData(
            age: age,
            biologicalSex: biologicalSex,
            heightCm: height,
            weightKg: weight
        )
    }
}

// MARK: - Data Structures

/// Profile data fetched from HealthKit
struct HealthProfileData {
    let age: Int?
    let biologicalSex: HKBiologicalSex?
    let heightCm: Double?
    let weightKg: Double?

    var sexString: String? {
        switch biologicalSex {
        case .male: return "Male"
        case .female: return "Female"
        case .other: return "Other"
        default: return nil
        }
    }

    /// Calculate BMI if height and weight are available
    var bmi: Double? {
        guard let height = heightCm, let weight = weightKg, height > 0 else {
            return nil
        }
        let heightMeters = height / 100
        return weight / (heightMeters * heightMeters)
    }
}
