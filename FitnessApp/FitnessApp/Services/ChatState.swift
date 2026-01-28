import Foundation

/// Explicit states for the chat session - eliminates ambiguous states
enum ChatState: Equatable {
    case idle
    case preparingContext
    case streaming(progress: String)
    case error(message: String)
    case cancelling

    var isLoading: Bool {
        switch self {
        case .preparingContext, .streaming, .cancelling:
            return true
        case .idle, .error:
            return false
        }
    }

    var canSendMessage: Bool {
        self == .idle || self.isError
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var statusText: String {
        switch self {
        case .idle:
            return ""
        case .preparingContext:
            return "Thinking..."
        case .streaming:
            return "Responding..."
        case .error(let message):
            return message
        case .cancelling:
            return "Cancelling..."
        }
    }
}
