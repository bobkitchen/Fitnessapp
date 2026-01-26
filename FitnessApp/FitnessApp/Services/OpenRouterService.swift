import Foundation

/// Service for interacting with OpenRouter AI API
actor OpenRouterService {

    private let baseURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120     // Wait up to 2 min for response to start
        config.timeoutIntervalForResource = 600    // 10 min max for full streaming response
        config.waitsForConnectivity = true         // Handle network transitions
        self.session = URLSession(configuration: config)
    }

    // MARK: - Available Models

    enum AIModel: String, CaseIterable, Identifiable {
        // Premium Tier
        case claudeOpus4 = "anthropic/claude-opus-4"
        case claudeSonnet4 = "anthropic/claude-sonnet-4"
        case gpt4o = "openai/gpt-4o"
        case gpt4Turbo = "openai/gpt-4-turbo"

        // Mid Tier
        case gemini25Pro = "google/gemini-2.5-pro-preview"
        case gemini25Flash = "google/gemini-2.5-flash-preview"
        case claude35Haiku = "anthropic/claude-3.5-haiku"

        // Free Tier
        case llama370bFree = "meta-llama/llama-3.3-70b-instruct:free"
        case gemini20FlashFree = "google/gemini-2.0-flash-exp:free"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .claudeOpus4: return "Claude Opus 4"
            case .claudeSonnet4: return "Claude Sonnet 4"
            case .gpt4o: return "GPT-4o"
            case .gpt4Turbo: return "GPT-4 Turbo"
            case .gemini25Pro: return "Gemini 2.5 Pro"
            case .gemini25Flash: return "Gemini 2.5 Flash"
            case .claude35Haiku: return "Claude 3.5 Haiku"
            case .llama370bFree: return "Llama 3.3 70B (Free)"
            case .gemini20FlashFree: return "Gemini 2.0 Flash (Free)"
            }
        }

        var tier: String {
            switch self {
            case .claudeOpus4, .claudeSonnet4, .gpt4o, .gpt4Turbo:
                return "Premium"
            case .gemini25Pro, .gemini25Flash, .claude35Haiku:
                return "Mid"
            case .llama370bFree, .gemini20FlashFree:
                return "Free"
            }
        }

        var description: String {
            switch self {
            case .claudeOpus4: return "Highest quality reasoning"
            case .claudeSonnet4: return "Best balance quality/speed"
            case .gpt4o: return "Fast, high quality"
            case .gpt4Turbo: return "OpenAI flagship"
            case .gemini25Pro: return "Google's latest"
            case .gemini25Flash: return "Fast, efficient"
            case .claude35Haiku: return "Fast Claude"
            case .llama370bFree: return "Powerful, free"
            case .gemini20FlashFree: return "Fast, free"
            }
        }

        static var `default`: AIModel { .claudeSonnet4 }
    }

    // MARK: - Chat Completion

    /// Send a chat completion request
    func sendMessage(
        messages: [ChatMessage],
        model: AIModel = .default,
        systemPrompt: String? = nil
    ) async throws -> String {
        guard let apiKey = KeychainService.getOpenRouterAPIKey() else {
            throw OpenRouterError.noAPIKey
        }

        var allMessages: [[String: Any]] = []

        // Add system prompt if provided
        if let system = systemPrompt {
            allMessages.append([
                "role": "system",
                "content": system
            ])
        }

        // Add conversation messages
        for message in messages {
            allMessages.append([
                "role": message.role.rawValue,
                "content": message.content
            ])
        }

        let requestBody: [String: Any] = [
            "model": model.rawValue,
            "messages": allMessages,
            "temperature": 0.7,
            "max_tokens": 4096
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("AI Fitness Coach iOS", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("AI Fitness Coach", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data) {
                throw OpenRouterError.apiError(errorResponse.error.message)
            }
            throw OpenRouterError.httpError(httpResponse.statusCode)
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let content = completion.choices.first?.message.content else {
            throw OpenRouterError.noContent
        }

        return content
    }

    /// Send a streaming chat completion request
    func streamMessage(
        messages: [ChatMessage],
        model: AIModel = .default,
        systemPrompt: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        // Capture values needed for the detached task
        let apiKey = KeychainService.getOpenRouterAPIKey()
        let baseURL = self.baseURL
        let session = self.session

        return AsyncThrowingStream { continuation in
            // Use detached task to avoid actor isolation issues with streaming
            Task.detached {
                do {
                    guard let apiKey = apiKey else {
                        throw OpenRouterError.noAPIKey
                    }

                    var allMessages: [[String: Any]] = []

                    if let system = systemPrompt {
                        allMessages.append([
                            "role": "system",
                            "content": system
                        ])
                    }

                    for message in messages {
                        allMessages.append([
                            "role": message.role.rawValue,
                            "content": message.content
                        ])
                    }

                    let requestBody: [String: Any] = [
                        "model": model.rawValue,
                        "messages": allMessages,
                        "stream": true,
                        "temperature": 0.7,
                        "max_tokens": 4096
                    ]

                    var request = URLRequest(url: baseURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.setValue("AI Fitness Coach iOS", forHTTPHeaderField: "HTTP-Referer")
                    request.setValue("AI Fitness Coach", forHTTPHeaderField: "X-Title")
                    request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw OpenRouterError.invalidResponse
                    }

                    // Handle non-200 responses with better error messages
                    if httpResponse.statusCode != 200 {
                        // Try to collect error response body
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                            // Limit error body collection to prevent hanging
                            if errorBody.count > 1000 { break }
                        }

                        // Try to parse error message
                        if let data = errorBody.data(using: .utf8),
                           let errorResponse = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data) {
                            throw OpenRouterError.apiError(errorResponse.error.message)
                        }

                        throw OpenRouterError.httpError(httpResponse.statusCode)
                    }

                    var hasReceivedContent = false

                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let jsonString = String(line.dropFirst(6))

                            if jsonString == "[DONE]" {
                                break
                            }

                            if let data = jsonString.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                               let content = chunk.choices.first?.delta.content {
                                hasReceivedContent = true
                                continuation.yield(content)
                            }
                        }
                    }

                    // If we never received content, something went wrong
                    if !hasReceivedContent {
                        throw OpenRouterError.noContent
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Account Credits

    /// Fetch current account credits/balance
    func fetchCredits() async throws -> CreditsResponse {
        guard let apiKey = KeychainService.getOpenRouterAPIKey() else {
            throw OpenRouterError.noAPIKey
        }

        let creditsURL = URL(string: "https://openrouter.ai/api/v1/credits")!
        var request = URLRequest(url: creditsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenRouterError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data) {
                throw OpenRouterError.apiError(errorResponse.error.message)
            }
            throw OpenRouterError.httpError(httpResponse.statusCode)
        }

        let creditsResponse = try JSONDecoder().decode(CreditsResponseWrapper.self, from: data)
        return creditsResponse.data
    }

    // MARK: - Token Counting (Estimate)

    /// Rough token count estimate (4 chars per token average)
    func estimateTokenCount(_ text: String) -> Int {
        return text.count / 4
    }

    // MARK: - Memory Extraction

    /// Extract memorable facts from a conversation turn.
    /// Uses a fast/cheap model to analyze user messages for facts worth remembering.
    func extractMemories(
        userMessage: String,
        assistantResponse: String
    ) async throws -> [ExtractedMemoryData] {
        guard let apiKey = KeychainService.getOpenRouterAPIKey() else {
            throw OpenRouterError.noAPIKey
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
            "model": AIModel.gemini20FlashFree.rawValue,  // Fast, free model for extraction
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 500,
            "response_format": ["type": "json_object"]
        ]

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("AI Fitness Coach iOS", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("AI Fitness Coach", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            print("[OpenRouter] Memory extraction failed with status: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            return []
        }

        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        guard let content = completion.choices.first?.message.content,
              let jsonData = content.data(using: .utf8) else {
            return []
        }

        do {
            let extraction = try JSONDecoder().decode(MemoryExtractionResponse.self, from: jsonData)
            return extraction.memories.map { memory in
                ExtractedMemoryData(
                    content: memory.content,
                    category: memory.category,
                    expiresInDays: memory.expiresInDays
                )
            }
        } catch {
            print("[OpenRouter] Failed to parse memory extraction: \(error)")
            return []
        }
    }
}

// MARK: - Memory Extraction Types

nonisolated struct ExtractedMemoryData: Sendable {
    let content: String
    let category: String
    let expiresInDays: Int?
}

nonisolated struct MemoryExtractionResponse: Codable, Sendable {
    let memories: [ExtractedMemory]

    struct ExtractedMemory: Codable, Sendable {
        let content: String
        let category: String
        let expiresInDays: Int?
    }
}

// MARK: - Data Types

nonisolated struct ChatMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date

    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date()) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
    }
}

nonisolated enum MessageRole: String, Codable, Sendable {
    case user
    case assistant
    case system
}

// MARK: - API Response Types

nonisolated struct ChatCompletionResponse: Codable, Sendable {
    let id: String
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Codable, Sendable {
        let index: Int
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }

    struct Message: Codable, Sendable {
        let role: String
        let content: String
    }

    struct Usage: Codable, Sendable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

nonisolated struct StreamChunk: Codable, Sendable {
    let choices: [StreamChoice]

    struct StreamChoice: Codable, Sendable {
        let delta: Delta
    }

    struct Delta: Codable, Sendable {
        let content: String?
    }
}

nonisolated struct OpenRouterErrorResponse: Codable, Sendable {
    let error: ErrorDetail

    struct ErrorDetail: Codable, Sendable {
        let message: String
        let type: String?
        let code: String?
    }
}

nonisolated struct CreditsResponseWrapper: Codable, Sendable {
    let data: CreditsResponse
}

nonisolated struct CreditsResponse: Codable, Sendable {
    let totalCredits: Double
    let totalUsage: Double

    enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }

    /// Remaining balance (credits - usage)
    var balance: Double {
        totalCredits - totalUsage
    }

    /// Formatted balance string
    var formattedBalance: String {
        String(format: "$%.2f", balance)
    }
}

// MARK: - Errors

enum OpenRouterError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case httpError(Int)
    case apiError(String)
    case noContent
    case streamingError

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Please add your OpenRouter API key in Settings."
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return message
        case .noContent:
            return "No content in response"
        case .streamingError:
            return "Error during streaming response"
        }
    }
}
