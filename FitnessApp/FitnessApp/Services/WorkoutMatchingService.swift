import Foundation
import SwiftData

/// Result of matching a TrainingPeaks workout to a HealthKit workout
struct WorkoutMatchResult {
    let workout: WorkoutRecord
    let confidenceScore: Double      // 0-1 normalized score
    let matchDetails: MatchDetails

    struct MatchDetails {
        let timeDifferenceSeconds: TimeInterval
        let durationDifferencePercent: Double
        let activityTypeMatched: Bool
        let distanceDifferencePercent: Double?
    }

    /// Whether this is a high-confidence match
    var isHighConfidence: Bool {
        confidenceScore >= 0.7
    }

    /// Human-readable description of match quality
    var qualityDescription: String {
        switch confidenceScore {
        case 0.9...: return "Excellent match"
        case 0.7..<0.9: return "Good match"
        case 0.5..<0.7: return "Possible match"
        default: return "Low confidence"
        }
    }
}

/// Service to match TrainingPeaks workouts to HealthKit workouts
@MainActor
final class WorkoutMatchingService {

    private let modelContext: ModelContext

    // Matching tolerances
    private let maxTimeDifferenceSeconds: TimeInterval = 120  // ±2 minutes for precise time
    private let maxDurationDifferencePercent: Double = 0.10   // ±10% (widened from 5%)
    private let maxDistanceDifferencePercent: Double = 0.05   // ±5% (widened from 3%)
    private let minMatchScore: Double = 50                     // Lowered from 70 to allow more matches

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Find the best matching HealthKit workout for a TrainingPeaks workout
    /// - Parameters:
    ///   - tpWorkout: The parsed TrainingPeaks workout data
    ///   - searchWindow: How many days before/after to search (default ±2 days)
    /// - Returns: The best match if found with confidence score, or nil if no good match
    func findMatch(for tpWorkout: TPWorkoutData, searchWindow: Int = 2) throws -> WorkoutMatchResult? {
        // Fetch candidate workouts within the search window
        // Don't filter by activity type initially - let scoring handle it
        let candidates = try fetchCandidates(
            around: tpWorkout.startDate,
            windowDays: searchWindow,
            activityCategory: nil  // Search all activities, score will prefer matching type
        )

        guard !candidates.isEmpty else {
            print("[WorkoutMatching] No candidates found in search window")
            return nil
        }

        print("[WorkoutMatching] Found \(candidates.count) candidates for matching")

        // Score each candidate
        var bestMatch: (workout: WorkoutRecord, score: Double, details: WorkoutMatchResult.MatchDetails)?

        for candidate in candidates {
            if let result = scoreMatch(candidate: candidate, tpWorkout: tpWorkout) {
                if bestMatch == nil || result.score > bestMatch!.score {
                    bestMatch = result
                }
            }
        }

        // Return best match if it meets minimum threshold
        guard let match = bestMatch else {
            print("[WorkoutMatching] No candidates met matching criteria")
            return nil
        }

        // Normalize score to 0-1 range (max possible is 105)
        let normalizedScore = min(1.0, match.score / 105.0)

        print("[WorkoutMatching] Best match score: \(String(format: "%.1f", match.score)) (\(String(format: "%.0f%%", normalizedScore * 100)) confidence)")

        return WorkoutMatchResult(
            workout: match.workout,
            confidenceScore: normalizedScore,
            matchDetails: match.details
        )
    }

    /// Find all potential matches for a TrainingPeaks workout
    /// Returns all candidates with their scores, sorted by confidence
    func findAllMatches(for tpWorkout: TPWorkoutData, searchWindow: Int = 3) throws -> [WorkoutMatchResult] {
        let candidates = try fetchCandidates(
            around: tpWorkout.startDate,
            windowDays: searchWindow,
            activityCategory: nil  // Don't filter by activity type - let scoring handle it
        )

        print("[Matching] Searching \(candidates.count) candidates for \(tpWorkout.activityType) on \(tpWorkout.startDate)")

        var matches: [WorkoutMatchResult] = []

        for candidate in candidates {
            if let result = scoreMatch(candidate: candidate, tpWorkout: tpWorkout) {
                // Max possible score is now ~120 (50 time + 30 duration + 25 activity + 15 distance)
                let normalizedScore = min(1.0, result.score / 120.0)
                matches.append(WorkoutMatchResult(
                    workout: candidate,
                    confidenceScore: normalizedScore,
                    matchDetails: result.details
                ))
            }
        }

        print("[Matching] Found \(matches.count) potential matches")

        // Sort by confidence, highest first
        return matches.sorted { $0.confidenceScore > $1.confidenceScore }
    }

    // MARK: - Private Methods

    /// Fetch candidate workouts from the database
    private func fetchCandidates(
        around date: Date,
        windowDays: Int,
        activityCategory: ActivityCategory?
    ) throws -> [WorkoutRecord] {
        let calendar = Calendar.current
        let startOfTargetDay = calendar.startOfDay(for: date)

        guard let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: startOfTargetDay),
              let windowEnd = calendar.date(byAdding: .day, value: windowDays + 1, to: startOfTargetDay) else {
            return []
        }

        var descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate<WorkoutRecord> { workout in
                workout.startDate >= windowStart && workout.startDate < windowEnd
            },
            sortBy: [SortDescriptor(\.startDate, order: .forward)]
        )
        descriptor.fetchLimit = 50  // Reasonable limit for performance

        var candidates = try modelContext.fetch(descriptor)

        // Filter by activity category if specified
        if let category = activityCategory {
            candidates = candidates.filter { $0.activityCategory == category }
        }

        return candidates
    }

    /// Score a candidate workout against the TP workout
    /// Returns nil if the candidate doesn't meet minimum criteria
    private func scoreMatch(
        candidate: WorkoutRecord,
        tpWorkout: TPWorkoutData
    ) -> (workout: WorkoutRecord, score: Double, details: WorkoutMatchResult.MatchDetails)? {
        var score = 0.0
        let calendar = Calendar.current

        // Determine if we have a precise time or just a date
        // If the TP time is midnight or very close to current time, treat it as "date only"
        let tpHour = calendar.component(.hour, from: tpWorkout.startDate)
        let tpMinute = calendar.component(.minute, from: tpWorkout.startDate)
        let timeSinceTPDate = abs(Date().timeIntervalSince(tpWorkout.startDate))

        // Consider time "imprecise" if:
        // 1. It's exactly midnight (00:00), or
        // 2. It was set very recently (within last 5 minutes) suggesting it was set to current time
        let hasImpreciseTime = (tpHour == 0 && tpMinute == 0) || timeSinceTPDate < 300

        // Time match (50 points max)
        let timeDiff = abs(candidate.startDate.timeIntervalSince(tpWorkout.startDate))
        let sameDay = calendar.isDate(candidate.startDate, inSameDayAs: tpWorkout.startDate)

        if hasImpreciseTime {
            // When time is imprecise, award points for same-day match
            if sameDay {
                score += 40  // Same day match when time is unknown
                print("[Matching] Same-day match (imprecise time): \(candidate.dateFormatted)")
            } else {
                // Different day - still allow if within 1 day (TP might show yesterday's workout)
                let dayDiff = abs(calendar.dateComponents([.day], from: tpWorkout.startDate, to: candidate.startDate).day ?? 999)
                if dayDiff <= 1 {
                    score += 20  // Adjacent day
                    print("[Matching] Adjacent-day match: \(candidate.dateFormatted)")
                } else {
                    return nil  // Too far apart
                }
            }
        } else {
            // Precise time matching
            if timeDiff < 60 {
                score += 50  // Within 1 minute: full points
            } else if timeDiff < 120 {
                score += 35  // Within 2 minutes: good match
            } else if timeDiff < 300 {
                score += 20  // Within 5 minutes: possible match
            } else if sameDay {
                score += 10  // Same day but different time
            } else {
                return nil  // Time too far off
            }
        }

        // Duration match (30 points max) - INCREASED importance
        let durationDiff = abs(candidate.durationSeconds - tpWorkout.duration) / max(1, tpWorkout.duration)

        if durationDiff < 0.02 {
            score += 30  // Within 2%: excellent match
        } else if durationDiff < 0.05 {
            score += 25  // Within 5%: very good
        } else if durationDiff < 0.10 {
            score += 15  // Within 10%: acceptable
        } else if durationDiff < 0.20 {
            score += 5   // Within 20%: marginal
        }

        // Activity type match (25 points) - INCREASED importance
        let activityTypeMatched = candidate.activityCategory == tpWorkout.activityCategory
        if activityTypeMatched {
            score += 25
        }

        // Distance match (15 points max, if available) - INCREASED importance
        var distanceDiff: Double?
        if let tpDist = tpWorkout.distance, let hkDist = candidate.distanceMeters, tpDist > 0 {
            distanceDiff = abs(hkDist - tpDist) / tpDist

            if distanceDiff! < 0.02 {
                score += 15  // Within 2%
            } else if distanceDiff! < 0.05 {
                score += 10  // Within 5%
            } else if distanceDiff! < 0.10 {
                score += 5   // Within 10%
            }
        }

        print("[Matching] Candidate \(candidate.activityCategory.rawValue) on \(candidate.dateFormatted): score=\(score), timeDiff=\(Int(timeDiff))s, durationDiff=\(String(format: "%.1f%%", durationDiff * 100)), activityMatch=\(activityTypeMatched)")

        // Only return if score meets minimum threshold
        guard score >= minMatchScore else {
            return nil
        }

        let details = WorkoutMatchResult.MatchDetails(
            timeDifferenceSeconds: timeDiff,
            durationDifferencePercent: durationDiff,
            activityTypeMatched: activityTypeMatched,
            distanceDifferencePercent: distanceDiff
        )

        return (candidate, score, details)
    }
}

// MARK: - Convenience Extensions

extension WorkoutMatchResult.MatchDetails {
    /// Human-readable time difference
    var timeDifferenceFormatted: String {
        if timeDifferenceSeconds < 60 {
            return "< 1 min"
        }
        let minutes = Int(timeDifferenceSeconds / 60)
        return "\(minutes) min"
    }

    /// Human-readable duration difference
    var durationDifferenceFormatted: String {
        String(format: "%.1f%%", durationDifferencePercent * 100)
    }
}
