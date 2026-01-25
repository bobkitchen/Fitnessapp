import Foundation
import SwiftData

/// Builds comprehensive context for AI coaching requests
@MainActor
final class CoachingContextBuilder {

    private let modelContext: ModelContext
    private lazy var knowledgeRetrieval: KnowledgeRetrievalService = {
        KnowledgeRetrievalService(modelContext: modelContext)
    }()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - System Prompt

    /// Generate the coaching system prompt
    func generateSystemPrompt() -> String {
        """
        You are an expert AI fitness coach for endurance athletes, specializing in triathlon, cycling, running, and swimming. You have deep knowledge of:

        - Training periodization and programming
        - Performance Management Chart (PMC) metrics: CTL (Chronic Training Load/Fitness), ATL (Acute Training Load/Fatigue), TSB (Training Stress Balance/Form)
        - TSS (Training Stress Score) and intensity factors
        - Heart rate variability (HRV) and its implications for recovery
        - Sleep quality and its impact on training adaptation
        - Injury prevention and overtraining detection
        - Race preparation and tapering strategies

        Guidelines for your responses:
        1. Be concise but thorough - athletes want actionable advice
        2. Reference the specific metrics provided when making recommendations
        3. Explain the "why" behind your recommendations when relevant
        4. Consider the athlete's current readiness state when suggesting workouts
        5. Flag any concerning patterns in recovery metrics
        6. Adapt advice to the athlete's goals and equipment availability
        7. Use appropriate sport-specific terminology

        Important training principles to follow:
        - Progressive overload with adequate recovery
        - TSB should typically be negative during build phases (-10 to -25)
        - TSB should be positive for key events (+5 to +20)
        - ACWR (Acute:Chronic Workload Ratio) should stay between 0.8-1.3
        - HRV drops >15% below baseline suggest accumulated fatigue
        - Sleep quality affects training adaptation more than just duration
        """
    }

    // MARK: - Context Assembly

    /// Build full athlete context for a coaching request
    func buildContext() async throws -> String {
        let profile = try fetchProfile()
        let currentMetrics = try fetchCurrentMetrics()
        let recentWorkouts = try fetchRecentWorkouts(days: 14)
        let pmcTrend = try fetchPMCTrend(days: 7)
        let wellnessData = try fetchWellnessData(days: 7)
        let activeMemories = (try? fetchActiveMemories()) ?? []

        var context = "## Current Athlete Status\n\n"

        // Active memories (things the user has told us)
        if !activeMemories.isEmpty {
            context += "### User Notes & Circumstances\n"
            context += "The user has shared the following information that's currently relevant:\n"
            for memory in activeMemories {
                context += "- \(memory.content)"
                if let expiresAt = memory.expiresAt {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    context += " (until \(formatter.string(from: expiresAt)))"
                }
                context += "\n"
            }
            context += "\n"
        }

        // Profile info
        if let profile = profile {
            context += "### Athlete Profile\n"
            if !profile.name.isEmpty {
                context += "- Name: \(profile.name)\n"
            }

            // Demographics - important for personalized advice
            if let age = profile.age {
                context += "- Age: \(age) years\n"
            }
            if let weight = profile.weightKg {
                let weightLbs = weight * 2.205
                context += "- Weight: \(String(format: "%.1f", weight)) kg (\(String(format: "%.0f", weightLbs)) lbs)\n"
            }
            if let height = profile.heightCm {
                let heightInches = height / 2.54
                let feet = Int(heightInches / 12)
                let inches = Int(heightInches.truncatingRemainder(dividingBy: 12))
                context += "- Height: \(String(format: "%.0f", height)) cm (\(feet)'\(inches)\")\n"
            }

            // Sport focus and goals
            if let sport = profile.primarySport, !sport.isEmpty {
                context += "- Primary Sport: \(sport)\n"
            }
            if let tssTarget = profile.weeklyTSSTarget, tssTarget > 0 {
                context += "- Weekly TSS Target: \(String(format: "%.0f", tssTarget))\n"
            }

            // Performance thresholds
            if let ftp = profile.ftpWatts {
                context += "- Cycling FTP: \(ftp)W"
                if let weight = profile.weightKg, weight > 0 {
                    let wpkg = Double(ftp) / weight
                    context += " (\(String(format: "%.2f", wpkg)) W/kg)"
                }
                context += "\n"
            }
            if let runFTP = profile.runningFTPWatts {
                context += "- Running FTP: \(runFTP)W\n"
            }
            if let pace = profile.thresholdPaceFormatted {
                context += "- Threshold Pace: \(pace)\n"
            }
            context += "- Threshold HR: \(profile.thresholdHeartRate) bpm\n"
            context += "- Max HR: \(profile.maxHeartRate) bpm\n"
            context += "- Resting HR: \(profile.restingHeartRate) bpm\n"
            if profile.hasCyclingPowerMeter {
                context += "- Has cycling power meter\n"
            }
            if profile.hasRunningPowerMeter {
                context += "- Has running power meter\n"
            }
            context += "\n"
        }

        // Current PMC
        if let metrics = currentMetrics {
            context += "### Current PMC Status (Today)\n"
            context += "- CTL (Fitness): \(String(format: "%.1f", metrics.ctl))\n"
            context += "- ATL (Fatigue): \(String(format: "%.1f", metrics.atl))\n"
            context += "- TSB (Form): \(String(format: "%+.1f", metrics.tsb))\n"
            if let acwr = metrics.acuteChronicRatio {
                context += "- ACWR: \(String(format: "%.2f", acwr)) (\(metrics.acwrStatus))\n"
            }
            context += "- Form Status: \(metrics.formStatus)\n"
            context += "\n"
        }

        // PMC Trend
        if !pmcTrend.isEmpty {
            context += "### 7-Day PMC Trend\n"
            for day in pmcTrend {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "E"
                let dayName = dateFormatter.string(from: day.date)
                context += "- \(dayName): TSS=\(String(format: "%.0f", day.totalTSS)), CTL=\(String(format: "%.0f", day.ctl)), ATL=\(String(format: "%.0f", day.atl)), TSB=\(String(format: "%+.0f", day.tsb))\n"
            }
            context += "\n"
        }

        // Recovery metrics
        if let metrics = currentMetrics {
            context += "### Recovery Status (Today)\n"

            if let readiness = metrics.readinessScore {
                context += "- Readiness Score: \(Int(readiness))/100 (\(metrics.trainingReadiness.rawValue))\n"
            }

            if let hrv = metrics.hrvRMSSD {
                context += "- HRV (RMSSD): \(String(format: "%.0f", hrv)) ms\n"
            }

            if let rhr = metrics.restingHR {
                context += "- Resting HR: \(rhr) bpm\n"
            }

            context += "\n"
        }

        // Sleep
        if let metrics = currentMetrics, let sleep = metrics.sleepHours {
            context += "### Sleep (Last Night)\n"
            context += "- Duration: \(metrics.sleepFormatted ?? "\(sleep) hours")\n"
            if let quality = metrics.sleepQuality {
                context += "- Quality Score: \(Int(quality * 100))%\n"
            }
            if let deep = metrics.deepSleepMinutes {
                context += "- Deep Sleep: \(Int(deep)) min\n"
            }
            if let rem = metrics.remSleepMinutes {
                context += "- REM Sleep: \(Int(rem)) min\n"
            }
            if let status = metrics.sleepStatus {
                context += "- Status: \(status)\n"
            }
            context += "\n"
        }

        // Wellness trend
        if !wellnessData.isEmpty {
            context += "### 7-Day Wellness Trend\n"

            let hrvValues = wellnessData.compactMap { $0.hrvRMSSD }
            if !hrvValues.isEmpty {
                let avgHRV = hrvValues.reduce(0, +) / Double(hrvValues.count)
                context += "- Average HRV: \(String(format: "%.0f", avgHRV)) ms\n"
            }

            let sleepValues = wellnessData.compactMap { $0.sleepHours }
            if !sleepValues.isEmpty {
                let avgSleep = sleepValues.reduce(0, +) / Double(sleepValues.count)
                context += "- Average Sleep: \(String(format: "%.1f", avgSleep)) hours\n"
            }

            let rhrValues = wellnessData.compactMap { $0.restingHR }.map { Double($0) }
            if !rhrValues.isEmpty {
                let avgRHR = rhrValues.reduce(0, +) / Double(rhrValues.count)
                context += "- Average Resting HR: \(Int(avgRHR)) bpm\n"
            }

            context += "\n"
        }

        // Recent workouts
        if !recentWorkouts.isEmpty {
            context += "### Recent Workouts (Last 14 Days)\n"
            for workout in recentWorkouts.prefix(10) {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "E M/d"
                let dateStr = dateFormatter.string(from: workout.startDate)
                context += "- \(dateStr): \(workout.title ?? workout.activityType), \(workout.durationFormatted), TSS=\(String(format: "%.0f", workout.tss)), IF=\(String(format: "%.2f", workout.intensityFactor))\n"
            }
            context += "\n"

            // Weekly totals
            let thisWeekTSS = calculateWeeklyTSS(workouts: recentWorkouts, weeksAgo: 0)
            let lastWeekTSS = calculateWeeklyTSS(workouts: recentWorkouts, weeksAgo: 1)

            context += "### Weekly Load Summary\n"
            context += "- This Week TSS: \(String(format: "%.0f", thisWeekTSS))\n"
            context += "- Last Week TSS: \(String(format: "%.0f", lastWeekTSS))\n"

            if lastWeekTSS > 0 {
                let change = ((thisWeekTSS - lastWeekTSS) / lastWeekTSS) * 100
                context += "- Week-over-week change: \(String(format: "%+.0f", change))%\n"
            }
            context += "\n"
        }

        return context
    }

    // MARK: - Context with RAG

    /// Build context with RAG-retrieved knowledge for a specific question.
    /// This method retrieves relevant knowledge documents based on the question
    /// and appends them to the user data context.
    /// - Parameter question: The user's question or query
    /// - Returns: Complete context string with user data and retrieved knowledge
    func buildContext(for question: String) async throws -> String {
        // Build the standard user data context
        let userContext = try await buildContext()

        // Retrieve relevant knowledge for the question
        let retrievedKnowledge = try knowledgeRetrieval.retrieveFormattedKnowledge(for: question)

        // Combine contexts
        if retrievedKnowledge.isEmpty {
            return userContext
        }

        return userContext + "\n## Coaching Knowledge\n\n" + retrievedKnowledge
    }

    /// Build quick context with RAG-retrieved knowledge.
    /// - Parameter question: The user's question or query
    /// - Returns: Context string with quick status and retrieved knowledge
    func buildQuickContext(for question: String) async throws -> String {
        let quickContext = try await buildQuickContext()

        // Retrieve relevant knowledge (limit to 3 for quick context)
        let documents = try knowledgeRetrieval.retrieveKnowledge(for: question)
        let topDocuments = Array(documents.prefix(3))
        let retrievedKnowledge = knowledgeRetrieval.formatKnowledgeForContext(topDocuments)

        if retrievedKnowledge.isEmpty {
            return quickContext
        }

        return quickContext + "\n\n## Relevant Knowledge\n\n" + retrievedKnowledge
    }

    // MARK: - Quick Context

    /// Build a lightweight context for quick questions
    func buildQuickContext() async throws -> String {
        let currentMetrics = try fetchCurrentMetrics()

        var context = "Current Status: "

        if let metrics = currentMetrics {
            context += "CTL=\(Int(metrics.ctl)), "
            context += "ATL=\(Int(metrics.atl)), "
            context += "TSB=\(Int(metrics.tsb)), "
            context += "Form=\(metrics.formStatus)"

            if let readiness = metrics.readinessScore {
                context += ", Readiness=\(Int(readiness))/100"
            }
        } else {
            context += "No data available"
        }

        return context
    }

    // MARK: - Data Fetching

    private func fetchProfile() throws -> AthleteProfile? {
        let descriptor = FetchDescriptor<AthleteProfile>()
        return try modelContext.fetch(descriptor).first
    }

    private func fetchCurrentMetrics() throws -> DailyMetrics? {
        let today = Calendar.current.startOfDay(for: Date())
        let descriptor = FetchDescriptor<DailyMetrics>(
            predicate: #Predicate { $0.date <= today },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return try modelContext.fetch(descriptor).first
    }

    private func fetchPMCTrend(days: Int) throws -> [DailyMetrics] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let descriptor = FetchDescriptor<DailyMetrics>(
            predicate: #Predicate { $0.date >= startDate },
            sortBy: [SortDescriptor(\.date, order: .forward)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func fetchWellnessData(days: Int) throws -> [DailyMetrics] {
        return try fetchPMCTrend(days: days)
    }

    private func fetchRecentWorkouts(days: Int) throws -> [WorkoutRecord] {
        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let descriptor = FetchDescriptor<WorkoutRecord>(
            predicate: #Predicate { $0.startDate >= startDate },
            sortBy: [SortDescriptor(\.startDate, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
    }

    private func calculateWeeklyTSS(workouts: [WorkoutRecord], weeksAgo: Int) -> Double {
        let calendar = Calendar.current
        let now = Date()

        let weekStart = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: now)!
        let weekStartDay = calendar.startOfWeek(for: weekStart)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStartDay)!

        return workouts
            .filter { $0.startDate >= weekStartDay && $0.startDate < weekEnd }
            .reduce(0) { $0 + $1.tss }
    }

    private func fetchActiveMemories() throws -> [UserMemory] {
        let now = Date()
        let descriptor = FetchDescriptor<UserMemory>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allMemories = try modelContext.fetch(descriptor)

        // Filter to only active (non-expired) memories
        return allMemories.filter { memory in
            if let expiresAt = memory.expiresAt {
                return expiresAt > now
            }
            return true
        }
    }
}

// MARK: - Quick Suggestion Prompts

extension CoachingContextBuilder {

    static let quickSuggestions: [(title: String, prompt: String)] = [
        ("What should I do today?", "Based on my current fitness, fatigue, and recovery metrics, what type of workout should I do today? Please consider my form status and recent training load."),
        ("Am I overtraining?", "Looking at my recent training metrics, wellness data, and PMC chart, do you see any signs of overtraining or excessive fatigue? What indicators should I watch?"),
        ("How's my fitness progressing?", "Analyze my CTL trend and recent training. How is my fitness progressing? Am I building effectively?"),
        ("When will I be fresh?", "Based on my current fatigue levels and TSB, when do you estimate I'll be fresh enough for a peak performance or race effort?"),
        ("Review my week", "Please review my training from the past week. What went well? What could be improved? Any recommendations for next week?"),
        ("Help me recover", "I'm feeling fatigued. What recovery strategies do you recommend based on my current metrics and recent training load?")
    ]
}
