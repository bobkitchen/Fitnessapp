//
//  KnowledgeRetrievalService.swift
//  FitnessApp
//
//  Created by Claude on 2026-01-24.
//

import Foundation
import SwiftData

/// Service for retrieving relevant coaching knowledge based on user questions.
/// Implements keyword-based retrieval with category inference and relevance scoring.
@MainActor
final class KnowledgeRetrievalService {
    private let modelContext: ModelContext

    /// Number of top documents to return
    private let topK: Int

    init(modelContext: ModelContext, topK: Int = 5) {
        self.modelContext = modelContext
        self.topK = topK
    }

    // MARK: - Public API

    /// Retrieves the most relevant knowledge documents for a given question.
    /// - Parameter question: The user's question or query
    /// - Returns: Array of relevant CoachingKnowledge documents, ranked by relevance
    func retrieveKnowledge(for question: String) throws -> [CoachingKnowledge] {
        let allKnowledge = try fetchAllKnowledge()
        guard !allKnowledge.isEmpty else { return [] }

        let questionKeywords = extractKeywords(from: question)
        let inferredCategories = inferCategories(from: question)

        // Score each document
        var scoredDocuments: [(document: CoachingKnowledge, score: Double)] = []

        for document in allKnowledge {
            let score = calculateRelevanceScore(
                document: document,
                questionKeywords: questionKeywords,
                inferredCategories: inferredCategories
            )
            if score > 0 {
                scoredDocuments.append((document, score))
            }
        }

        // Sort by score descending and take top K
        scoredDocuments.sort { $0.score > $1.score }
        return Array(scoredDocuments.prefix(topK).map(\.document))
    }

    /// Formats retrieved knowledge documents for injection into the coaching context.
    /// - Parameter documents: Array of knowledge documents
    /// - Returns: Formatted string suitable for LLM context
    func formatKnowledgeForContext(_ documents: [CoachingKnowledge]) -> String {
        guard !documents.isEmpty else { return "" }

        var sections: [String] = []

        for document in documents {
            var section = "### \(document.title)"
            if let subcategory = document.subcategory {
                section += " (\(subcategory))"
            }
            section += "\n\(document.content)"
            sections.append(section)
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Keyword Extraction

    /// Extracts meaningful keywords from a question.
    /// Removes stop words and normalizes to lowercase.
    private func extractKeywords(from text: String) -> Set<String> {
        let normalized = text.lowercased()

        // Tokenize by splitting on non-alphanumeric characters
        let tokens = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0.count > 2 }

        // Remove stop words
        let stopWords: Set<String> = [
            "the", "a", "an", "is", "are", "was", "were", "be", "been", "being",
            "have", "has", "had", "do", "does", "did", "will", "would", "could",
            "should", "may", "might", "must", "can", "this", "that", "these",
            "those", "i", "you", "he", "she", "it", "we", "they", "what", "which",
            "who", "whom", "when", "where", "why", "how", "all", "each", "every",
            "both", "few", "more", "most", "other", "some", "such", "no", "nor",
            "not", "only", "own", "same", "so", "than", "too", "very", "just",
            "also", "now", "here", "there", "then", "any", "about", "into",
            "through", "during", "before", "after", "above", "below", "from",
            "up", "down", "in", "out", "on", "off", "over", "under", "again",
            "further", "once", "and", "but", "if", "or", "because", "as", "until",
            "while", "of", "at", "by", "for", "with", "to", "my", "your", "his",
            "her", "its", "our", "their", "me", "him", "us", "them", "myself",
            "yourself", "himself", "herself", "itself", "ourselves", "themselves"
        ]

        return Set(tokens.filter { !stopWords.contains($0) })
    }

    // MARK: - Category Inference

    /// Infers likely knowledge categories from a question.
    private func inferCategories(from question: String) -> Set<String> {
        let lowercased = question.lowercased()
        var categories: Set<String> = []

        // Training-related patterns
        let trainingPatterns = [
            "train", "workout", "exercise", "run", "cycle", "swim", "bike",
            "interval", "tempo", "threshold", "long run", "easy", "hard",
            "periodization", "base", "build", "peak", "taper", "race",
            "marathon", "triathlon", "5k", "10k", "half marathon", "ultra",
            "tss", "ctl", "atl", "tsb", "fitness", "fatigue", "form",
            "volume", "intensity", "mileage", "pace", "speed", "endurance"
        ]

        // Nutrition-related patterns
        let nutritionPatterns = [
            "eat", "food", "diet", "nutrition", "fuel", "carb", "protein",
            "fat", "calorie", "hydrat", "drink", "meal", "snack", "breakfast",
            "lunch", "dinner", "pre-workout", "post-workout", "recovery drink",
            "gel", "electrolyte", "macro", "micro", "vitamin", "supplement"
        ]

        // Recovery-related patterns
        let recoveryPatterns = [
            "recover", "rest", "sleep", "hrv", "heart rate variability",
            "resting heart rate", "fatigue", "tired", "sore", "ache",
            "overtrain", "burnout", "stress", "relax", "massage", "foam roll",
            "stretch", "mobility", "readiness", "adaptation"
        ]

        // Injury-related patterns
        let injuryPatterns = [
            "injury", "injur", "pain", "hurt", "strain", "sprain", "tear",
            "tendon", "muscle", "joint", "knee", "ankle", "hip", "back",
            "shoulder", "it band", "plantar", "achilles", "shin splint",
            "prevent", "prehab", "rehab", "return to", "heal"
        ]

        // Mental-related patterns
        let mentalPatterns = [
            "motivation", "motivat", "mental", "psych", "mindset", "focus",
            "concentrat", "anxiety", "nervous", "confidence", "goal",
            "habit", "routine", "discipline", "consistency", "setback",
            "plateau", "stuck", "bored", "burnout"
        ]

        // Age-specific patterns
        let agePatterns = [
            "age", "older", "young", "masters", "40", "50", "60", "70",
            "senior", "youth", "kid", "teen", "aging", "mature"
        ]

        // Weight loss patterns
        let weightLossPatterns = [
            "weight", "lose", "fat", "body composition", "lean", "slim",
            "calories", "deficit", "burn", "metabolism", "scale"
        ]

        // Health literacy patterns
        let healthPatterns = [
            "health", "doctor", "medical", "blood", "pressure", "cholesterol",
            "diabetes", "heart", "condition", "medication", "symptom"
        ]

        // Lifestyle patterns
        let lifestylePatterns = [
            "life", "balance", "work", "family", "time", "schedule",
            "habit", "routine", "consistent", "sustainable", "long-term"
        ]

        // Check each pattern set
        if trainingPatterns.contains(where: { lowercased.contains($0) }) {
            categories.insert(CoachingKnowledge.Category.training.rawValue)
        }
        if nutritionPatterns.contains(where: { lowercased.contains($0) }) {
            categories.insert(CoachingKnowledge.Category.nutrition.rawValue)
        }
        if recoveryPatterns.contains(where: { lowercased.contains($0) }) {
            categories.insert(CoachingKnowledge.Category.recovery.rawValue)
        }
        if injuryPatterns.contains(where: { lowercased.contains($0) }) {
            categories.insert(CoachingKnowledge.Category.injury.rawValue)
        }
        if mentalPatterns.contains(where: { lowercased.contains($0) }) {
            categories.insert(CoachingKnowledge.Category.mental.rawValue)
        }
        if agePatterns.contains(where: { lowercased.contains($0) }) {
            categories.insert(CoachingKnowledge.Category.ageSpecific.rawValue)
        }
        if weightLossPatterns.contains(where: { lowercased.contains($0) }) {
            categories.insert(CoachingKnowledge.Category.weightLoss.rawValue)
        }
        if healthPatterns.contains(where: { lowercased.contains($0) }) {
            categories.insert(CoachingKnowledge.Category.healthLiteracy.rawValue)
        }
        if lifestylePatterns.contains(where: { lowercased.contains($0) }) {
            categories.insert(CoachingKnowledge.Category.lifestyle.rawValue)
        }

        return categories
    }

    // MARK: - Relevance Scoring

    /// Calculates a relevance score for a document based on keyword and category matching.
    private func calculateRelevanceScore(
        document: CoachingKnowledge,
        questionKeywords: Set<String>,
        inferredCategories: Set<String>
    ) -> Double {
        var score: Double = 0

        // Keyword matching (weighted by number of matches)
        let documentKeywords = Set(document.keywords.map { $0.lowercased() })
        let keywordMatches = questionKeywords.intersection(documentKeywords).count
        score += Double(keywordMatches) * 2.0

        // Partial keyword matching (substring matches)
        for questionKeyword in questionKeywords {
            for docKeyword in documentKeywords {
                if docKeyword.contains(questionKeyword) || questionKeyword.contains(docKeyword) {
                    if docKeyword != questionKeyword {
                        score += 0.5  // Partial match bonus
                    }
                }
            }
        }

        // Category matching
        if inferredCategories.contains(document.category) {
            score += 3.0
        }

        // Subcategory matching (if question keywords match subcategory)
        if let subcategory = document.subcategory {
            let subcategoryTokens = Set(subcategory.lowercased().components(separatedBy: "_"))
            if !questionKeywords.intersection(subcategoryTokens).isEmpty {
                score += 1.5
            }
        }

        // Title matching
        let titleKeywords = extractKeywords(from: document.title)
        let titleMatches = questionKeywords.intersection(titleKeywords).count
        score += Double(titleMatches) * 1.5

        // Content matching (lightweight - just check for question keyword presence)
        let contentLower = document.content.lowercased()
        for keyword in questionKeywords {
            if contentLower.contains(keyword) {
                score += 0.3
            }
        }

        return score
    }

    // MARK: - Data Fetching

    private func fetchAllKnowledge() throws -> [CoachingKnowledge] {
        let descriptor = FetchDescriptor<CoachingKnowledge>(
            sortBy: [SortDescriptor(\.category), SortDescriptor(\.title)]
        )
        return try modelContext.fetch(descriptor)
    }
}

// MARK: - Convenience Extension

extension KnowledgeRetrievalService {
    /// Retrieves and formats knowledge for a question in one call.
    func retrieveFormattedKnowledge(for question: String) throws -> String {
        let documents = try retrieveKnowledge(for: question)
        return formatKnowledgeForContext(documents)
    }
}
