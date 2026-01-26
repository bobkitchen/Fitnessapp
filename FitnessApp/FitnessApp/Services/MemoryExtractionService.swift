import Foundation
import SwiftData

/// Completely isolated memory extraction - no actor dependencies
/// Uses its own URLSession and Task.detached to avoid any contention with streaming
enum MemoryExtractionService {

    /// Fire-and-forget memory extraction
    /// Runs entirely in a detached task with its own URLSession
    static func extractAndSave(
        userMessage: String,
        assistantResponse: String,
        modelContext: ModelContext
    ) {
        // Capture the container for the detached task
        let container = modelContext.container

        Task.detached(priority: .utility) {
            // 1. Make API call with isolated URLSession
            let memories = await extractMemoriesDirectly(
                userMessage: userMessage,
                assistantResponse: assistantResponse
            )

            guard !memories.isEmpty else {
                print("[Memory] No memories to extract")
                return
            }

            // 2. Save on MainActor with fresh context
            await MainActor.run {
                let context = ModelContext(container)
                saveMemories(memories, userMessage: userMessage, context: context)
            }
        }
    }

    /// Direct API call without going through OpenRouterService actor
    private static func extractMemoriesDirectly(
        userMessage: String,
        assistantResponse: String
    ) async -> [ExtractedMemoryData] {
        guard let apiKey = KeychainService.getOpenRouterAPIKey() else {
            print("[Memory] No API key")
            return []
        }

        let today = DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .none)

        let systemPrompt = """
            You are a memory extraction system. Analyze the user's message for facts that should be remembered for future coaching conversations.

            Extract ONLY concrete, actionable facts the user explicitly states about themselves. Examples:
            - Schedule changes: "I'm on vacation for 2 weeks", "I'll be traveling next month"
            - Injuries/health: "I have a sore knee", "I'm recovering from a cold"
            - Goals: "I'm training for a marathon in April", "I want to lose 10 pounds"
            - Preferences: "I prefer morning workouts", "I don't have access to a pool"
            - Lifestyle: "I work night shifts", "I have a newborn at home"

            DO NOT extract:
            - Questions the user is asking
            - General statements or opinions
            - Information already implied by their training data
            - Temporary moods or feelings

            Today's date is: \(today)

            Respond with JSON only. If no memories should be extracted, return: {"memories": []}

            For each memory, determine:
            - content: A clear, specific statement (e.g., "User is on vacation until February 7, 2026")
            - category: One of: schedule, injury, goal, preference, health, lifestyle, general
            - expiresInDays: Number of days until this fact expires (null if permanent)
              - Vacation/travel: Calculate days until end date
              - Injuries: Usually 14-30 days unless specified
              - Goals with deadlines: Days until the event
              - Preferences: null (permanent)
            """

        let userPrompt = """
            User message: "\(userMessage)"

            Assistant response: "\(assistantResponse)"

            Extract any facts worth remembering from the user's message.
            """

        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userPrompt]
        ]

        let requestBody: [String: Any] = [
            "model": "google/gemini-2.0-flash-exp:free",
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 500,
            "response_format": ["type": "json_object"]
        ]

        // Use a fresh, isolated URLSession
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }

        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("AI Fitness Coach iOS", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("AI Fitness Coach", forHTTPHeaderField: "X-Title")
        request.timeoutInterval = 30

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("[Memory] API failed: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return []
            }

            // Parse response
            let completion = try JSONDecoder().decode(MemoryCompletionResponse.self, from: data)
            guard let content = completion.choices.first?.message.content,
                  let jsonData = content.data(using: .utf8) else {
                print("[Memory] No content in response")
                return []
            }

            let extraction = try JSONDecoder().decode(MemoryExtractionResponseLocal.self, from: jsonData)
            return extraction.memories.map {
                ExtractedMemoryData(content: $0.content, category: $0.category, expiresInDays: $0.expiresInDays)
            }
        } catch {
            print("[Memory] Error: \(error.localizedDescription)")
            return []
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

// MARK: - Local Response Types (don't depend on OpenRouterService)

private struct MemoryCompletionResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: Message
    }

    struct Message: Codable {
        let content: String
    }
}

private struct MemoryExtractionResponseLocal: Codable {
    let memories: [Memory]

    struct Memory: Codable {
        let content: String
        let category: String
        let expiresInDays: Int?
    }
}
