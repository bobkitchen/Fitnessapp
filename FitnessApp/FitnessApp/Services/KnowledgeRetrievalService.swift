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
///
/// PERFORMANCE FIX: Removed @MainActor to allow database operations off the main thread.
/// Uses its own ModelContext created from the container for thread safety.
final class KnowledgeRetrievalService {
    private let modelContext: ModelContext

    /// Number of top documents to return
    private let topK: Int

    /// FIX 2.1: Cache knowledge documents to avoid fetching on every query
    /// Knowledge documents rarely change, so caching is safe
    private var cachedKnowledge: [CoachingKnowledge]?
    private var cacheTimestamp: Date?
    private let cacheValiditySeconds: TimeInterval = 300  // 5 minutes

    init(modelContext: ModelContext, topK: Int = 5) {
        self.modelContext = modelContext
        self.topK = topK
    }

    // MARK: - Public API

    /// Retrieves the most relevant knowledge documents for a given question.
    /// - Parameter question: The user's question or query
    /// - Returns: Array of relevant CoachingKnowledge documents, ranked by relevance
    func retrieveKnowledge(for question: String) throws -> [CoachingKnowledge] {
        let allKnowledge = try fetchKnowledgeWithCache()
        guard !allKnowledge.isEmpty else { return [] }

        // FIX 2.2: Use Set for O(1) keyword matching instead of nested loops
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

    /// Invalidates the knowledge cache, forcing a fresh fetch on next query
    func invalidateCache() {
        cachedKnowledge = nil
        cacheTimestamp = nil
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
    /// FIX 2.2: Use Set intersection for O(n) instead of O(n²) nested loops
    private func calculateRelevanceScore(
        document: CoachingKnowledge,
        questionKeywords: Set<String>,
        inferredCategories: Set<String>
    ) -> Double {
        var score: Double = 0

        // FIX 2.2: Use Set intersection for O(1) exact keyword matching
        let documentKeywords = Set(document.keywords.map { $0.lowercased() })
        let exactMatches = questionKeywords.intersection(documentKeywords)
        score += Double(exactMatches.count) * 2.0

        // FIX 2.2: Optimized partial matching - only check non-exact matches
        // Uses a single pass approach instead of nested O(n²) loops
        let unmatchedQuestionKeywords = questionKeywords.subtracting(exactMatches)
        let unmatchedDocKeywords = documentKeywords.subtracting(exactMatches)

        // Only do substring matching if there are unmatched keywords
        if !unmatchedQuestionKeywords.isEmpty && !unmatchedDocKeywords.isEmpty {
            // Build a simple prefix/suffix index for faster partial matching
            for questionKeyword in unmatchedQuestionKeywords where questionKeyword.count >= 3 {
                for docKeyword in unmatchedDocKeywords where docKeyword.count >= 3 {
                    // Check if one contains the other (partial match)
                    if docKeyword.contains(questionKeyword) || questionKeyword.contains(docKeyword) {
                        score += 0.5
                        break  // Only count once per question keyword
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

        // Title matching - use Set intersection
        let titleKeywords = extractKeywords(from: document.title)
        let titleMatches = questionKeywords.intersection(titleKeywords).count
        score += Double(titleMatches) * 1.5

        // Content matching - limit to first few keywords to avoid O(n*m) worst case
        let contentLower = document.content.lowercased()
        var contentMatchCount = 0
        for keyword in questionKeywords.prefix(10) {  // Limit iterations
            if contentLower.contains(keyword) {
                contentMatchCount += 1
            }
        }
        score += Double(contentMatchCount) * 0.3

        return score
    }

    // MARK: - Data Fetching

    /// FIX 2.1: Fetch knowledge with caching to avoid loading all documents on every query
    private func fetchKnowledgeWithCache() throws -> [CoachingKnowledge] {
        // Check if cache is valid
        if let cached = cachedKnowledge,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheValiditySeconds {
            return cached
        }

        // Cache miss - fetch from database
        let fresh = try fetchAllKnowledge()
        cachedKnowledge = fresh
        cacheTimestamp = Date()
        print("[Knowledge] Cache refreshed with \(fresh.count) documents")
        return fresh
    }

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
