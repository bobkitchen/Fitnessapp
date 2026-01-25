import Foundation
import SwiftData

/// Simple memory extraction - no actors, no complexity
enum MemoryExtractionService {

    /// Fire-and-forget memory extraction
    /// - API call runs in background
    /// - Save runs on MainActor (like RAG does)
    static func extractAndSave(
        userMessage: String,
        assistantResponse: String,
        modelContext: ModelContext
    ) async {
        // 1. API call (OpenRouterService handles its own isolation)
        let openRouter = OpenRouterService()

        let memories: [ExtractedMemoryData]
        do {
            memories = try await openRouter.extractMemories(
                userMessage: userMessage,
                assistantResponse: assistantResponse
            )
        } catch {
            print("[Memory] API error: \(error.localizedDescription)")
            return
        }

        guard !memories.isEmpty else {
            print("[Memory] No memories to extract")
            return
        }

        // 2. Save on MainActor (same pattern as RAG)
        await MainActor.run {
            saveMemories(memories, userMessage: userMessage, context: modelContext)
        }
    }

    @MainActor
    private static func saveMemories(
        _ memories: [ExtractedMemoryData],
        userMessage: String,
        context: ModelContext
    ) {
        // Fetch existing once
        let descriptor = FetchDescriptor<UserMemory>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let existingContents = existing.map { $0.content.lowercased() }

        var saved = 0
        for extracted in memories {
            // Skip duplicates
            let lower = extracted.content.lowercased()
            let isDupe = existingContents.contains {
                $0.contains(String(lower.prefix(50))) || lower.contains(String($0.prefix(50)))
            }
            if isDupe { continue }

            // Calculate expiration
            var expiresAt: Date?
            if let days = extracted.expiresInDays {
                expiresAt = Calendar.current.date(byAdding: .day, value: days, to: Date())
            }

            let category = MemoryCategory(rawValue: extracted.category) ?? .general
            let memory = UserMemory(
                content: extracted.content,
                category: category,
                expiresAt: expiresAt,
                sourceContext: String(userMessage.prefix(200))
            )
            context.insert(memory)
            saved += 1
        }

        if saved > 0 {
            try? context.save()
            print("[Memory] Saved \(saved) memories")
        }
    }
}
