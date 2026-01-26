import SwiftUI
import SwiftData

/// AI Coaching chat view
struct CoachView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var streamingText = ""
    @State private var errorMessage: String?
    @FocusState private var isInputFocused: Bool

    @AppStorage("defaultAIModel") private var defaultModelId = "anthropic/claude-sonnet-4"

    private let openRouterService = OpenRouterService()

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
                if messages.isEmpty && !isLoading && !isInputFocused {
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
                    .disabled(messages.isEmpty && !isLoading)
                }
            }
            .alert("Error", isPresented: .init(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Messages View

    @ViewBuilder
    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(messages) { message in
                        ChatBubble(message: message)
                            .id(message.id)
                    }

                    // Streaming message
                    if isLoading && !streamingText.isEmpty {
                        ChatBubble(message: ChatMessage(
                            role: .assistant,
                            content: streamingText
                        ))
                        .id("streaming")
                    }

                    // Loading indicator
                    if isLoading && streamingText.isEmpty {
                        HStack {
                            ProgressView()
                                .padding(.trailing, 8)
                            Text("Thinking...")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .id("loading")
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture {
                isInputFocused = false
            }
            .onChange(of: messages.count) {
                withAnimation {
                    proxy.scrollTo(messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: streamingText) {
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
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
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
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

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(inputText.isEmpty ? Color.textTertiary : Color.accentSecondary)
            }
            .disabled(inputText.isEmpty || isLoading)
        }
        .padding(Spacing.md)
        .background(Color.backgroundSecondary)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        inputText = ""

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        Task {
            await sendToAI()
        }
    }

    private func sendQuickSuggestion(_ prompt: String) {
        let userMessage = ChatMessage(role: .user, content: prompt)
        messages.append(userMessage)

        Task {
            await sendToAI()
        }
    }

    private func clearChat() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            messages.removeAll()
            streamingText = ""
            errorMessage = nil
        }
    }

    private func sendToAI() async {
        isLoading = true
        streamingText = ""

        do {
            // Get the user's question for RAG retrieval
            let userQuestion = messages.last(where: { $0.role == .user })?.content ?? ""

            // Build context with RAG knowledge retrieval
            let contextBuilder = CoachingContextBuilder(modelContext: modelContext)
            let context = try await contextBuilder.buildContext(for: userQuestion)
            let systemPrompt = contextBuilder.generateSystemPrompt()

            // Add context to first message
            var contextualMessages = messages
            if let firstIndex = contextualMessages.firstIndex(where: { $0.role == .user }) {
                let original = contextualMessages[firstIndex]
                contextualMessages[firstIndex] = ChatMessage(
                    id: original.id,
                    role: .user,
                    content: "\(context)\n\n## Question\n\(original.content)",
                    timestamp: original.timestamp
                )
            }

            // Stream response
            let stream = await openRouterService.streamMessage(
                messages: contextualMessages,
                model: selectedModel,
                systemPrompt: systemPrompt
            )

            for try await chunk in stream {
                streamingText += chunk
            }

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

        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        streamingText = ""
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

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

            if !isUser { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Markdown Text View

/// Renders markdown content with proper formatting
struct MarkdownText: View {
    let content: String

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

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: Spacing.xs) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: Spacing.xs) {
                        Text("•")
                            .font(AppFont.bodyMedium)
                            .foregroundStyle(Color.accentPrimary)
                        renderInlineMarkdown(item)
                            .font(AppFont.bodyMedium)
                            .fixedSize(horizontal: false, vertical: true)
                    }
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
                        renderInlineMarkdown(item)
                            .font(AppFont.bodyMedium)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

        case .codeBlock(let code):
            Text(code)
                .font(.system(size: 13, design: .monospaced))
                .padding(Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.backgroundPrimary)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))

        case .blockquote(let text):
            HStack(alignment: .top, spacing: Spacing.xs) {
                Rectangle()
                    .fill(Color.accentSecondary)
                    .frame(width: 3)
                renderInlineMarkdown(text)
                    .font(AppFont.bodyMedium)
                    .italic()
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.leading, Spacing.xs)
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

// MARK: - Preview

#Preview {
    CoachView()
        .modelContainer(for: [AthleteProfile.self, DailyMetrics.self, WorkoutRecord.self, UserMemory.self], inMemory: true)
}
