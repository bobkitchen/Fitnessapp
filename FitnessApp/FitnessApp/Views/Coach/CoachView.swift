import SwiftUI
import SwiftData

/// AI Coaching chat view
struct CoachView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var chatState: ChatState = .idle
    @State private var streamingText = ""
    @State private var errorMessage: String?
    @State private var showingProfileSheet = false
    @State private var currentTask: Task<Void, Never>?
    @FocusState private var isInputFocused: Bool

    // FIX 4.1: Track last failed message for retry functionality
    @State private var lastFailedMessage: String?
    // FIX 4.2: Track scroll position for "jump to latest" button
    @State private var isScrolledUp = false

    @AppStorage("defaultAIModel") private var defaultModelId = "anthropic/claude-sonnet-4"

    private let openRouterService = OpenRouterService()

    /// Timeout for AI requests (45 seconds)
    private let requestTimeout: TimeInterval = 45

    /// Get the selected model from settings
    private var selectedModel: OpenRouterService.AIModel {
        OpenRouterService.AIModel.allCases.first { $0.rawValue == defaultModelId } ?? .default
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages list
                messagesView

                // Quick suggestions (if no messages and not typing)
                if messages.isEmpty && !chatState.isLoading && !isInputFocused {
                    quickSuggestions
                }

                // Input bar
                inputBar
            }
            .background(Color.backgroundPrimary)
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isInputFocused = false
                        clearChat()
                    } label: {
                        Label("New Chat", systemImage: "plus.bubble")
                    }
                    .foregroundStyle(Color.accentPrimary)
                    .disabled(messages.isEmpty && !chatState.isLoading)
                    // FIX 3.1: VoiceOver accessibility
                    .accessibilityLabel("Start new chat")
                    .accessibilityHint("Double tap to clear current conversation and start fresh")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ProfileAvatarButton(showingProfile: $showingProfileSheet)
                        // FIX 3.1: VoiceOver accessibility
                        .accessibilityLabel("Profile settings")
                        .accessibilityHint("Double tap to view and edit your profile")
                }
            }
            .sheet(isPresented: $showingProfileSheet) {
                ProfileSheetView()
            }
            // FIX 4.1: Enhanced error alert with retry button
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                // Show retry button if we have a failed message to retry
                if lastFailedMessage != nil {
                    Button("Retry") {
                        retryLastMessage()
                    }
                }
                Button("OK", role: .cancel) {
                    errorMessage = nil
                    lastFailedMessage = nil
                }
            } message: {
                Text(errorMessage ?? "Something went wrong")
            }
            .preferredColorScheme(.dark)
            .onDisappear {
                // Cancel any running task when view disappears
                cancelCurrentTask()
            }
        }
    }

    // MARK: - Messages View

    @ViewBuilder
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(messages) { message in
                            ChatBubble(message: message)
                                .id(message.id)
                        }

                        // Streaming message - use plain Text to avoid MarkdownText crash
                        // MarkdownText.parseBlocks() crashes on incomplete markdown during streaming
                        if chatState.isLoading && !streamingText.isEmpty {
                            HStack {
                                VStack(alignment: .leading, spacing: Spacing.xxs) {
                                    Text(streamingText)
                                        .font(AppFont.bodyMedium)
                                        .textSelection(.enabled)
                                    Text(Date(), style: .time)
                                        .font(AppFont.captionSmall)
                                        .foregroundStyle(Color.textTertiary)
                                }
                                .padding(Spacing.sm)
                                .background(Color.backgroundTertiary)
                                .foregroundStyle(Color.textPrimary)
                                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                                Spacer(minLength: 40)
                            }
                            .id("streaming")
                        }

                        // Loading indicator
                        if chatState.isLoading && streamingText.isEmpty {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text(chatState.statusText.isEmpty ? "Thinking..." : chatState.statusText)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                            .id("loading")
                            // FIX 3.1: VoiceOver accessibility for loading state
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("AI coach is thinking")
                            .accessibilityAddTraits(.updatesFrequently)
                        }

                        // Invisible anchor at the bottom for scroll detection
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding()
                }
                .scrollDismissesKeyboard(.interactively)
                .contentShape(Rectangle())
                .onTapGesture {
                    isInputFocused = false
                }
                .onChange(of: messages.count) {
                    isScrolledUp = false  // Reset when new messages arrive
                    withAnimation {
                        proxy.scrollTo(messages.last?.id, anchor: .bottom)
                    }
                }
                .onChange(of: streamingText) {
                    // Scroll without animation during streaming to reduce layout overhead
                    // and prevent executor starvation from rapid onChange triggers
                    // FIX 4.2: Only auto-scroll if user hasn't manually scrolled up
                    if chatState.isLoading && !isScrolledUp {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    } else if !chatState.isLoading {
                        withAnimation {
                            proxy.scrollTo("streaming", anchor: .bottom)
                        }
                    }
                }

                // FIX 4.2: "Jump to latest" button when scrolled up during streaming
                if isScrolledUp && chatState.isLoading {
                    Button {
                        isScrolledUp = false
                        withAnimation {
                            if !streamingText.isEmpty {
                                proxy.scrollTo("streaming", anchor: .bottom)
                            } else {
                                proxy.scrollTo("loading", anchor: .bottom)
                            }
                        }
                    } label: {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "arrow.down")
                            Text("Jump to latest")
                        }
                        .font(AppFont.labelMedium)
                        .padding(.horizontal, Spacing.md)
                        .padding(.vertical, Spacing.sm)
                        .background(Color.accentSecondary)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                    }
                    .padding(.bottom, Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityLabel("Jump to latest message")
                    .accessibilityHint("Double tap to scroll to the newest content")
                }
            }
            // Detect manual scroll-up gesture
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        // User is scrolling up (dragging down)
                        if value.translation.height > 50 && chatState.isLoading {
                            isScrolledUp = true
                        }
                    }
            )
        }
    }

    // MARK: - Quick Suggestions

    @ViewBuilder
    private var quickSuggestions: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Quick Questions".uppercased())
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)
                .padding(.horizontal, Spacing.md)
                // FIX 3.1: VoiceOver accessibility
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(CoachingContextBuilder.quickSuggestions, id: \.title) { suggestion in
                        Button {
                            sendQuickSuggestion(suggestion.prompt)
                        } label: {
                            Text(suggestion.title)
                                .font(AppFont.labelMedium)
                                .padding(.horizontal, Spacing.md)
                                .padding(.vertical, Spacing.xs)
                                .background(Color.backgroundTertiary)
                                .foregroundStyle(Color.textSecondary)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.accentSecondary.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        // FIX 3.1: VoiceOver accessibility for suggestion buttons
                        .accessibilityLabel(suggestion.title)
                        .accessibilityHint("Double tap to ask the coach this question")
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
            // FIX 3.1: Mark suggestions container for accessibility
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Quick question suggestions")
        }
        .padding(.vertical, Spacing.md)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Input Bar

    @ViewBuilder
    private var inputBar: some View {
        HStack(spacing: Spacing.sm) {
            TextField("Ask your coach...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(AppFont.bodyMedium)
                .padding(Spacing.sm)
                .background(Color.backgroundTertiary)
                .foregroundStyle(Color.textPrimary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
                .lineLimit(1...5)
                .focused($isInputFocused)
                // FIX 3.1: VoiceOver accessibility
                .accessibilityLabel("Message input")
                .accessibilityHint("Type your question for the AI coach")

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(inputText.isEmpty ? Color.textTertiary : Color.accentSecondary)
            }
            .disabled(inputText.isEmpty || chatState.isLoading)
            // FIX 3.1: VoiceOver accessibility for send button
            .accessibilityLabel("Send message")
            .accessibilityHint(inputText.isEmpty ? "Enter a message first" : "Double tap to send your question")
        }
        .padding(Spacing.md)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard chatState.canSendMessage else { return }

        inputText = ""

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        startAITask()
    }

    private func sendQuickSuggestion(_ prompt: String) {
        guard chatState.canSendMessage else { return }

        let userMessage = ChatMessage(role: .user, content: prompt)
        messages.append(userMessage)

        startAITask()
    }

    private func clearChat() {
        // Cancel any running task
        cancelCurrentTask()

        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            messages.removeAll()
            streamingText = ""
            errorMessage = nil
            lastFailedMessage = nil
            chatState = .idle
        }
    }

    // FIX 4.1: Retry the last failed message
    private func retryLastMessage() {
        guard let failedMessage = lastFailedMessage else { return }
        errorMessage = nil
        lastFailedMessage = nil

        // Remove the failed user message from the list if it exists
        // (it was added before the error occurred)
        if let lastUserIndex = messages.lastIndex(where: { $0.role == .user && $0.content == failedMessage }) {
            messages.remove(at: lastUserIndex)
        }

        // Re-add and retry
        let userMessage = ChatMessage(role: .user, content: failedMessage)
        messages.append(userMessage)
        startAITask()
    }

    /// Cancel the current AI task if running
    private func cancelCurrentTask() {
        currentTask?.cancel()
        currentTask = nil
    }

    /// Start the AI task with proper lifecycle management
    private func startAITask() {
        // Cancel any existing task first
        cancelCurrentTask()

        chatState = .preparingContext
        streamingText = ""

        currentTask = Task {
            await sendToAI()
        }
    }

    @MainActor
    private func sendToAI() async {
        // Get the user's question for RAG retrieval (declared outside do block for error handling)
        let userQuestion = messages.last(where: { $0.role == .user })?.content ?? ""

        // Ensure we reset state when task completes (for any reason)
        // Preserve error states so they aren't overwritten with .idle
        defer {
            if !Task.isCancelled && !chatState.isError {
                chatState = .idle
                streamingText = ""
            }
        }

        do {
            // Check for cancellation early
            try Task.checkCancellation()

            // Build context with RAG knowledge retrieval
            let contextBuilder = CoachingContextBuilder(modelContext: modelContext)

            // Wrap context building in timeout
            // FIX: Use defer to ensure cancelAll() runs even when timeout throws
            let context = try await withThrowingTaskGroup(of: String.self) { group in
                group.addTask {
                    try await contextBuilder.buildContext(for: userQuestion)
                }

                group.addTask {
                    try await Task.sleep(for: .seconds(self.requestTimeout))
                    throw ChatError.timeout
                }

                // CRITICAL FIX: Always cancel remaining tasks, even if we throw
                // Without defer, if the timeout task completes first, the context-building
                // task continues running in the background, wasting resources
                defer { group.cancelAll() }

                guard let result = try await group.next() else {
                    throw ChatError.timeout
                }
                return result
            }

            let systemPrompt = contextBuilder.generateSystemPrompt()

            // Check for cancellation after context building
            guard !Task.isCancelled else { return }

            // FIX: Validate context size doesn't exceed API token limits
            // Estimate tokens (rough: ~4 chars per token) and truncate if needed
            let maxContextTokens = 6000  // Leave room for response
            var truncatedContext = context
            let estimatedTokens = await openRouterService.estimateTokenCount(context + userQuestion)

            if estimatedTokens > maxContextTokens {
                // Truncate context to fit within limits
                // Keep the most important parts (beginning has profile/current status)
                let targetCharCount = maxContextTokens * 4
                if context.count > targetCharCount {
                    truncatedContext = String(context.prefix(targetCharCount))
                    // Try to end at a section boundary
                    if let lastSection = truncatedContext.range(of: "\n## ", options: .backwards) {
                        truncatedContext = String(truncatedContext[..<lastSection.lowerBound])
                    }
                    truncatedContext += "\n\n[Context truncated due to length]"
                    print("[Coach] Context truncated from \(context.count) to \(truncatedContext.count) chars")
                }
            }

            chatState = .streaming(progress: "")

            // Add context to first message
            var contextualMessages = messages
            if let firstIndex = contextualMessages.firstIndex(where: { $0.role == .user }) {
                let original = contextualMessages[firstIndex]
                contextualMessages[firstIndex] = ChatMessage(
                    id: original.id,
                    role: .user,
                    content: "\(truncatedContext)\n\n## Question\n\(original.content)",
                    timestamp: original.timestamp
                )
            }

            // Stream response with timeout
            let stream = await openRouterService.streamMessage(
                messages: contextualMessages,
                model: selectedModel,
                systemPrompt: systemPrompt
            )

            // Activity tracker for watchdog timeout
            let activityTracker = StreamActivityTracker()
            let streamTimeout: TimeInterval = 30

            // Start watchdog task that will cancel us if stream stalls
            let watchdogTask = Task.detached {
                while true {
                    try await Task.sleep(for: .seconds(5))
                    try Task.checkCancellation()
                    let elapsed = await activityTracker.timeSinceLastActivity()
                    if elapsed > streamTimeout {
                        print("[Coach] Watchdog: timeout after \(elapsed)s of inactivity")
                        // Don't throw - just return. The main task checks isCancelled.
                        return
                    }
                }
            }
            defer { watchdogTask.cancel() }

            // Batch UI updates to prevent executor starvation
            var buffer = ""
            var lastUpdateTime = Date()
            let updateInterval: TimeInterval = 0.05
            var consumedChunks = 0

            print("[Coach] Starting stream consumption with watchdog")
            for try await chunk in stream {
                consumedChunks += 1
                await activityTracker.touch()

                // Check for cancellation on each chunk
                try Task.checkCancellation()

                // Check watchdog status - if it completed, we timed out
                if watchdogTask.isCancelled == false {
                    // Watchdog still running, check if it detected timeout
                    let elapsed = await activityTracker.timeSinceLastActivity()
                    if elapsed > streamTimeout {
                        print("[Coach] Stream timeout after \(consumedChunks) chunks")
                        throw ChatError.timeout
                    }
                }

                buffer += chunk
                let now = Date()
                if now.timeIntervalSince(lastUpdateTime) >= updateInterval {
                    if consumedChunks % 20 == 0 {
                        print("[Coach] UI update #\(consumedChunks), text length: \(streamingText.count + buffer.count)")
                    }
                    streamingText += buffer
                    buffer = ""
                    lastUpdateTime = now
                }
            }

            // Flush any remaining buffer
            if !buffer.isEmpty {
                streamingText += buffer
            }
            print("[Coach] Exited stream loop after \(consumedChunks) chunks, final length: \(streamingText.count)")

            // Final cancellation check
            guard !Task.isCancelled else { return }

            // Add completed message
            let assistantMessage = ChatMessage(role: .assistant, content: streamingText)
            messages.append(assistantMessage)

            // Extract memories - completely fire and forget
            // The method handles its own Task.detached internally
            MemoryExtractionService.extractAndSave(
                userMessage: userQuestion,
                assistantResponse: streamingText,
                modelContext: modelContext
            )

        } catch is CancellationError {
            // Clean cancellation - state will be reset by defer
            return
        } catch ChatError.timeout {
            // FIX 4.1: Save failed message for retry
            lastFailedMessage = userQuestion
            chatState = .error(message: "Request timed out. Please try again.")
            errorMessage = "Request timed out. Please try again."
        } catch {
            // FIX 4.1: Save failed message for retry
            lastFailedMessage = userQuestion
            chatState = .error(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Chat Errors

enum ChatError: LocalizedError {
    case timeout

    var errorDescription: String? {
        switch self {
        case .timeout:
            return "Request timed out. Please try again."
        }
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    /// Format timestamp for accessibility
    private var accessibleTimestamp: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: Spacing.xxs) {
                if isUser {
                    Text(message.content)
                        .font(AppFont.bodyMedium)
                        .textSelection(.enabled)
                } else {
                    MarkdownText(message.content)
                        .textSelection(.enabled)
                }

                Text(message.timestamp, style: .time)
                    .font(AppFont.captionSmall)
                    .foregroundStyle(isUser ? Color.white.opacity(0.7) : Color.textTertiary)
            }
            .padding(Spacing.sm)
            .background(isUser ? Color.accentSecondary : Color.backgroundTertiary)
            .foregroundStyle(isUser ? .white : Color.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
            // FIX 3.1: VoiceOver accessibility for chat bubbles
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(isUser ? "You" : "Coach") said: \(message.content)")
            .accessibilityHint("Message sent at \(accessibleTimestamp)")

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Markdown Text View

/// Renders markdown content with proper formatting
struct MarkdownText: View {
    let content: String

    // FIX 3.2: Use ScaledMetric for Dynamic Type support in code blocks
    @ScaledMetric(relativeTo: .body) private var codeBlockFontSize: CGFloat = 13

    init(_ content: String) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    // MARK: - Block Types

    private enum MarkdownBlock {
        case paragraph(String)
        case heading(level: Int, text: String)
        case bulletList([String])
        case numberedList([String])
        case codeBlock(String)
        case blockquote(String)
    }

    // MARK: - Parsing

    private func parseBlocks() -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line - skip
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // Code block
            if trimmed.hasPrefix("```") {
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(codeLines.joined(separator: "\n")))
                i += 1
                continue
            }

            // Heading
            if let match = trimmed.firstMatch(of: /^(#{1,6})\s+(.+)$/) {
                let level = match.1.count
                let text = String(match.2)
                blocks.append(.heading(level: level, text: text))
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                var quoteLines: [String] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let quoteLine = lines[i].trimmingCharacters(in: .whitespaces)
                    quoteLines.append(String(quoteLine.dropFirst().trimmingCharacters(in: .whitespaces)))
                    i += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: " ")))
                continue
            }

            // Bullet list
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
                var items: [String] = []
                while i < lines.count {
                    let listLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if listLine.hasPrefix("- ") || listLine.hasPrefix("* ") || listLine.hasPrefix("• ") {
                        items.append(String(listLine.dropFirst(2)))
                        i += 1
                    } else if listLine.isEmpty {
                        i += 1
                        break
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items))
                continue
            }

            // Numbered list
            if let _ = trimmed.firstMatch(of: /^\d+\.\s+/) {
                var items: [String] = []
                while i < lines.count {
                    let listLine = lines[i].trimmingCharacters(in: .whitespaces)
                    if let match = listLine.firstMatch(of: /^\d+\.\s+(.+)$/) {
                        items.append(String(match.1))
                        i += 1
                    } else if listLine.isEmpty {
                        i += 1
                        break
                    } else {
                        break
                    }
                }
                blocks.append(.numberedList(items))
                continue
            }

            // Regular paragraph
            var paragraphLines: [String] = []
            while i < lines.count {
                let pLine = lines[i]
                let pTrimmed = pLine.trimmingCharacters(in: .whitespaces)
                if pTrimmed.isEmpty || pTrimmed.hasPrefix("#") || pTrimmed.hasPrefix("```") ||
                   pTrimmed.hasPrefix("- ") || pTrimmed.hasPrefix("* ") || pTrimmed.hasPrefix(">") ||
                   pTrimmed.firstMatch(of: /^\d+\.\s+/) != nil {
                    break
                }
                paragraphLines.append(pTrimmed)
                i += 1
            }
            if !paragraphLines.isEmpty {
                blocks.append(.paragraph(paragraphLines.joined(separator: " ")))
            }
        }

        return blocks
    }

    // MARK: - Rendering

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock) -> some View {
        switch block {
        case .paragraph(let text):
            renderInlineMarkdown(text)
                .font(AppFont.bodyMedium)

        case .heading(let level, let text):
            renderInlineMarkdown(text)
                .font(headingFont(for: level))
                .fontWeight(.semibold)
                .padding(.top, level == 1 ? Spacing.sm : Spacing.xs)
                // FIX 3.3: Add semantic heading role for VoiceOver
                .accessibilityAddTraits(.isHeader)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: Spacing.xs) {
                        Text("•")
                            .font(AppFont.bodyMedium)
                            .foregroundStyle(Color.accentPrimary)
                            .accessibilityHidden(true)  // Hide bullet from VoiceOver
                        renderInlineMarkdown(item)
                            .font(AppFont.bodyMedium)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // FIX 3.3: Combine list item for VoiceOver
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("List item: \(item)")
                }
            }

        case .numberedList(let items):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: Spacing.xs) {
                        Text("\(index + 1).")
                            .font(AppFont.bodyMedium)
                            .foregroundStyle(Color.accentPrimary)
                            .frame(minWidth: 20, alignment: .trailing)
                            .accessibilityHidden(true)  // Hide number from VoiceOver
                        renderInlineMarkdown(item)
                            .font(AppFont.bodyMedium)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // FIX 3.3: Combine numbered list item for VoiceOver
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Item \(index + 1): \(item)")
                }
            }

        case .codeBlock(let code):
            Text(code)
                // FIX 3.2: Use scaled font size for Dynamic Type support
                .font(.system(size: codeBlockFontSize, design: .monospaced))
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.backgroundPrimary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                // FIX 3.3: Mark code block for VoiceOver
                .accessibilityLabel("Code block: \(code)")

        case .blockquote(let text):
            HStack(alignment: .top, spacing: Spacing.xs) {
                Rectangle()
                    .fill(Color.accentSecondary)
                    .frame(width: 3)
                    .accessibilityHidden(true)  // Hide decorative element
                renderInlineMarkdown(text)
                    .font(AppFont.bodyMedium)
                    .italic()
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, Spacing.xs)
            // FIX 3.3: Mark blockquote for VoiceOver
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Quote: \(text)")
        }
    }

    private func headingFont(for level: Int) -> Font {
        switch level {
        case 1: return AppFont.titleLarge
        case 2: return AppFont.titleMedium
        case 3: return AppFont.labelLarge
        default: return AppFont.labelMedium
        }
    }

    /// Render inline markdown (bold, italic, code, links)
    private func renderInlineMarkdown(_ text: String) -> Text {
        // Try to use AttributedString for inline formatting
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attributed)
        }
        return Text(text)
    }
}

// MARK: - Stream Activity Tracker

/// Actor for thread-safe activity tracking during streaming.
/// Used by watchdog timeout to detect stalled streams.
private actor StreamActivityTracker {
    private var lastActivity = Date()

    func touch() {
        lastActivity = Date()
    }

    func timeSinceLastActivity() -> TimeInterval {
        Date().timeIntervalSince(lastActivity)
    }
}

// MARK: - Preview

#Preview {
    CoachView()
        .modelContainer(for: [AthleteProfile.self, DailyMetrics.self, WorkoutRecord.self, UserMemory.self], inMemory: true)
}
