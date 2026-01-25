//
//  CoachingKnowledge.swift
//  FitnessApp
//
//  Created by Claude on 2026-01-24.
//

import Foundation
import SwiftData

/// A knowledge document for RAG-based AI coaching retrieval.
/// Each document represents a discrete piece of coaching expertise that can be
/// retrieved based on user questions and context.
@Model
final class CoachingKnowledge {
    // MARK: - Identification

    var id: UUID
    var createdAt: Date
    var version: Int

    // MARK: - Classification

    /// Primary category (e.g., "training", "nutrition", "recovery")
    var category: String

    /// Optional subcategory for finer classification (e.g., "periodization", "race_nutrition")
    var subcategory: String?

    /// Human-readable title (e.g., "Marathon Taper Protocol")
    var title: String

    // MARK: - Content

    /// Full knowledge document content
    var content: String

    /// Keywords for search matching (stored as JSON array string)
    var keywordsRaw: String

    /// Goals this knowledge applies to (stored as JSON array string)
    var applicableGoalsRaw: String?

    /// Experience levels this applies to (stored as JSON array string)
    var applicableLevelsRaw: String?

    // MARK: - Computed Properties for Arrays

    var keywords: [String] {
        get {
            guard let data = keywordsRaw.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return array
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let string = String(data: data, encoding: .utf8) {
                keywordsRaw = string
            }
        }
    }

    var applicableGoals: [String]? {
        get {
            guard let raw = applicableGoalsRaw,
                  let data = raw.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return nil
            }
            return array
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue),
               let string = String(data: data, encoding: .utf8) {
                applicableGoalsRaw = string
            } else {
                applicableGoalsRaw = nil
            }
        }
    }

    var applicableLevels: [String]? {
        get {
            guard let raw = applicableLevelsRaw,
                  let data = raw.data(using: .utf8),
                  let array = try? JSONDecoder().decode([String].self, from: data) else {
                return nil
            }
            return array
        }
        set {
            if let newValue = newValue,
               let data = try? JSONEncoder().encode(newValue),
               let string = String(data: data, encoding: .utf8) {
                applicableLevelsRaw = string
            } else {
                applicableLevelsRaw = nil
            }
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        category: String,
        subcategory: String? = nil,
        title: String,
        content: String,
        keywords: [String],
        applicableGoals: [String]? = nil,
        applicableLevels: [String]? = nil,
        createdAt: Date = Date(),
        version: Int = 1
    ) {
        self.id = id
        self.category = category
        self.subcategory = subcategory
        self.title = title
        self.content = content
        self.keywordsRaw = "[]"
        self.applicableGoalsRaw = nil
        self.applicableLevelsRaw = nil
        self.createdAt = createdAt
        self.version = version

        // Set array properties after initialization
        self.keywords = keywords
        self.applicableGoals = applicableGoals
        self.applicableLevels = applicableLevels
    }
}

// MARK: - Knowledge Categories

extension CoachingKnowledge {
    /// Predefined knowledge categories
    enum Category: String, CaseIterable {
        case training = "training"
        case nutrition = "nutrition"
        case recovery = "recovery"
        case injury = "injury"
        case mental = "mental"
        case ageSpecific = "age_specific"
        case healthLiteracy = "health_literacy"
        case weightLoss = "weight_loss"
        case lifestyle = "lifestyle"

        var displayName: String {
            switch self {
            case .training: return "Endurance Training"
            case .nutrition: return "Nutrition"
            case .recovery: return "Recovery & Wellness"
            case .injury: return "Injury Prevention"
            case .mental: return "Mental Performance"
            case .ageSpecific: return "Age-Specific Guidance"
            case .healthLiteracy: return "Health Literacy"
            case .weightLoss: return "Weight Loss"
            case .lifestyle: return "Healthy Lifestyle"
            }
        }
    }

    /// Experience levels for knowledge applicability
    enum ExperienceLevel: String, CaseIterable {
        case beginner = "beginner"
        case intermediate = "intermediate"
        case advanced = "advanced"
        case elite = "elite"
    }
}

// MARK: - Import Support

extension CoachingKnowledge {
    /// Codable representation for JSON import
    struct ImportData: Codable {
        let category: String
        let subcategory: String?
        let title: String
        let content: String
        let keywords: [String]
        let applicableGoals: [String]?
        let applicableLevels: [String]?

        func toModel() -> CoachingKnowledge {
            CoachingKnowledge(
                category: category,
                subcategory: subcategory,
                title: title,
                content: content,
                keywords: keywords,
                applicableGoals: applicableGoals,
                applicableLevels: applicableLevels
            )
        }
    }
}
