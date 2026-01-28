import SwiftUI
import Observation

/// Shared service to provide readiness grade color across views
@Observable
final class ReadinessStateService {
    /// Current readiness score (0-100)
    var currentScore: Double?

    /// Returns the grade color based on current score
    var gradeColor: Color {
        guard let score = currentScore else {
            return Color.accentPrimary.opacity(0.5)
        }
        return LetterGrade.from(score: score).color
    }
}
