import Foundation
import SwiftData

/// Stores user-provided facts that the AI coach should remember across conversations.
/// These are automatically extracted from conversations when users share relevant information.
@Model
final class UserMemory {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date

    /// The memory content (e.g., "User is on vacation until February 7, 2026")
    var content: String

    /// Category for organization and retrieval
    var category: MemoryCategory

    /// Optional expiration date - memory becomes inactive after this date
    var expiresAt: Date?

    /// Source context - the conversation snippet that led to this memory
    var sourceContext: String?

    /// Whether this memory is currently active (not expired)
    var isActive: Bool {
        if let expiresAt {
            return expiresAt > Date()
        }
        return true
    }

    init(
        id: UUID = UUID(),
        content: String,
        category: MemoryCategory = .general,
        expiresAt: Date? = nil,
        sourceContext: String? = nil
    ) {
        self.id = id
        self.content = content
        self.category = category
        self.expiresAt = expiresAt
        self.sourceContext = sourceContext
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Memory Categories

enum MemoryCategory: String, Codable, CaseIterable {
    case schedule = "schedule"       // Vacation, travel, busy periods
    case injury = "injury"           // Current injuries or physical limitations
    case goal = "goal"               // Training goals, race targets
    case preference = "preference"   // Training preferences, equipment
    case health = "health"           // Health conditions, medications
    case lifestyle = "lifestyle"     // Work schedule, family commitments
    case general = "general"         // Other relevant information

    var displayName: String {
        switch self {
        case .schedule: return "Schedule"
        case .injury: return "Injury"
        case .goal: return "Goal"
        case .preference: return "Preference"
        case .health: return "Health"
        case .lifestyle: return "Lifestyle"
        case .general: return "General"
        }
    }

    var icon: String {
        switch self {
        case .schedule: return "calendar"
        case .injury: return "bandage"
        case .goal: return "flag"
        case .preference: return "slider.horizontal.3"
        case .health: return "heart"
        case .lifestyle: return "house"
        case .general: return "brain"
        }
    }
}

