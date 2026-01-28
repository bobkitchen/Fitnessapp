//
//  KnowledgeImportService.swift
//  FitnessApp
//
//  Created by Claude on 2026-01-24.
//

import Foundation
import SwiftData

/// Service for importing coaching knowledge from JSON files into SwiftData.
/// Handles initial seeding and version updates of the knowledge base.
@MainActor
final class KnowledgeImportService {
    private let modelContext: ModelContext

    /// Current version of the bundled knowledge base
    /// Update this when adding new knowledge files
    static let currentKnowledgeVersion = KnowledgeBaseConstants.currentVersion

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Public API

    /// Checks if the knowledge base needs to be seeded or updated.
    /// Call this on app launch.
    func seedKnowledgeIfNeeded() async throws {
        let storedVersion = UserDefaults.standard.integer(forKey: .knowledgeBaseVersion)

        if storedVersion == 0 {
            // First launch - seed the knowledge base
            try await seedInitialKnowledge()
            UserDefaults.standard.set(Self.currentKnowledgeVersion, forKey: .knowledgeBaseVersion)
        } else if storedVersion < Self.currentKnowledgeVersion {
            // Knowledge base update available
            try await updateKnowledgeBase(from: storedVersion)
            UserDefaults.standard.set(Self.currentKnowledgeVersion, forKey: .knowledgeBaseVersion)
        }
        // else: knowledge is up to date
    }

    /// Seeds the initial knowledge base from bundled JSON files.
    func seedInitialKnowledge() async throws {
        // Get all knowledge JSON files from the bundle
        let knowledgeFiles = findKnowledgeFiles()

        for fileURL in knowledgeFiles {
            try await importKnowledgeFile(at: fileURL)
        }

        try modelContext.save()
        print("Knowledge base seeded with \(knowledgeFiles.count) files")
    }

    /// Imports a single JSON file containing knowledge documents.
    func importKnowledgeFile(at url: URL) async throws {
        let data = try Data(contentsOf: url)
        let documents = try JSONDecoder().decode([CoachingKnowledge.ImportData].self, from: data)

        for importData in documents {
            let knowledge = importData.toModel()
            modelContext.insert(knowledge)
        }

        print("Imported \(documents.count) knowledge documents from \(url.lastPathComponent)")
    }

    /// Imports knowledge from a JSON string (useful for testing or dynamic updates).
    func importKnowledgeFromJSON(_ jsonString: String) throws {
        guard let data = jsonString.data(using: .utf8) else {
            throw KnowledgeImportError.invalidJSON
        }

        let documents = try JSONDecoder().decode([CoachingKnowledge.ImportData].self, from: data)

        for importData in documents {
            let knowledge = importData.toModel()
            modelContext.insert(knowledge)
        }

        try modelContext.save()
    }

    // MARK: - Private Helpers

    /// Finds all knowledge JSON files in the app bundle.
    private func findKnowledgeFiles() -> [URL] {
        guard let resourceURL = Bundle.main.resourceURL else { return [] }

        let knowledgeBaseURL = resourceURL.appendingPathComponent("KnowledgeBase")

        // Check if KnowledgeBase folder exists
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: knowledgeBaseURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            // Fallback: look for files with "knowledge" prefix in bundle root
            return findKnowledgeFilesInBundleRoot()
        }

        // Find all JSON files in KnowledgeBase folder
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: knowledgeBaseURL,
                includingPropertiesForKeys: nil
            )
            return contents.filter { $0.pathExtension == "json" }
        } catch {
            print("Error reading KnowledgeBase directory: \(error)")
            return []
        }
    }

    /// Fallback method to find knowledge files in bundle root.
    private func findKnowledgeFilesInBundleRoot() -> [URL] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: nil) else {
            return []
        }
        return urls.filter { $0.lastPathComponent.hasPrefix("knowledge_") }
    }

    /// Updates the knowledge base from an older version.
    private func updateKnowledgeBase(from oldVersion: Int) async throws {
        // For now, clear and re-seed. In the future, this could be more granular.
        try clearAllKnowledge()
        try await seedInitialKnowledge()
    }

    /// Clears all knowledge documents from the database.
    func clearAllKnowledge() throws {
        let descriptor = FetchDescriptor<CoachingKnowledge>()
        let allKnowledge = try modelContext.fetch(descriptor)

        for knowledge in allKnowledge {
            modelContext.delete(knowledge)
        }

        try modelContext.save()
    }

    /// Returns the count of knowledge documents in the database.
    func knowledgeCount() throws -> Int {
        let descriptor = FetchDescriptor<CoachingKnowledge>()
        return try modelContext.fetchCount(descriptor)
    }

    /// Returns knowledge documents by category.
    func knowledgeByCategory() throws -> [String: Int] {
        let descriptor = FetchDescriptor<CoachingKnowledge>()
        let allKnowledge = try modelContext.fetch(descriptor)

        var counts: [String: Int] = [:]
        for knowledge in allKnowledge {
            counts[knowledge.category, default: 0] += 1
        }
        return counts
    }
}

// MARK: - Errors

enum KnowledgeImportError: Error, LocalizedError {
    case invalidJSON
    case fileNotFound(String)
    case importFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return "Invalid JSON format"
        case .fileNotFound(let filename):
            return "Knowledge file not found: \(filename)"
        case .importFailed(let reason):
            return "Import failed: \(reason)"
        }
    }
}
