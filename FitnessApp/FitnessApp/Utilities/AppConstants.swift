//
//  AppConstants.swift
//  FitnessApp
//
//  Centralized constants to eliminate magic numbers and strings.
//

import Foundation

// MARK: - UserDefaults Keys

/// Type-safe UserDefaults keys to eliminate magic strings
enum UserDefaultsKey: String {
    /// Whether the user has completed the initial onboarding flow
    case hasCompletedOnboarding

    /// Whether HealthKit authorization has been attempted
    case hasAttemptedHealthKitAuth

    /// Whether profile data has been synced from HealthKit
    case hasSyncedProfileFromHealthKit

    /// Whether an OpenRouter API key has been saved
    case hasOpenRouterAPIKey

    /// Encoded sync statistics data
    case syncStatistics

    /// Current knowledge base version for migrations
    case knowledgeBaseVersion
}

/// Convenience extension for type-safe UserDefaults access
extension UserDefaults {
    func bool(forKey key: UserDefaultsKey) -> Bool {
        bool(forKey: key.rawValue)
    }

    func set(_ value: Bool, forKey key: UserDefaultsKey) {
        set(value, forKey: key.rawValue)
    }

    func integer(forKey key: UserDefaultsKey) -> Int {
        integer(forKey: key.rawValue)
    }

    func set(_ value: Int, forKey key: UserDefaultsKey) {
        set(value, forKey: key.rawValue)
    }

    func data(forKey key: UserDefaultsKey) -> Data? {
        data(forKey: key.rawValue)
    }

    func set(_ value: Data?, forKey key: UserDefaultsKey) {
        set(value, forKey: key.rawValue)
    }
}

// MARK: - PMC (Performance Management Chart) Constants

/// Constants for Performance Management Chart calculations
enum PMCConstants {
    /// Time constant for Chronic Training Load (CTL) - fitness
    /// Standard value: 42 days
    static let ctlTimeConstant: Double = 42

    /// Time constant for Acute Training Load (ATL) - fatigue
    /// Standard value: 7 days
    static let atlTimeConstant: Double = 7

    /// Decay factors derived from time constants
    /// CTL decay = e^(-1/42)
    static var ctlDecayFactor: Double {
        exp(-1.0 / ctlTimeConstant)
    }

    /// ATL decay = e^(-1/7)
    static var atlDecayFactor: Double {
        exp(-1.0 / atlTimeConstant)
    }
}

// MARK: - TSS (Training Stress Score) Constants

/// Constants for TSS calculations
enum TSSConstants {
    /// Normalized Power rolling average window (seconds)
    static let normalizedPowerWindowSeconds: Int = 30

    /// Standard FTP test duration (minutes)
    static let ftpTestDurationMinutes: Int = 20

    /// FTP adjustment factor (20-min power × 0.95 = estimated 1-hr power)
    static let ftpAdjustmentFactor: Double = 0.95

    /// Maximum reasonable TSS per hour (for validation)
    static let maxTSSPerHour: Double = 200

    /// Minimum workout duration for TSS calculation (seconds)
    static let minimumDurationForTSS: TimeInterval = 300  // 5 minutes
}

// MARK: - UI Constants

/// UI timing and animation constants
enum UIConstants {
    /// Streaming text update interval (seconds)
    static let streamingUpdateInterval: TimeInterval = 0.05

    /// Default animation duration
    static let defaultAnimationDuration: TimeInterval = 0.3

    /// Staggered animation delay per item
    static let staggeredAnimationDelay: TimeInterval = 0.05

    /// Pull-to-refresh debounce interval
    static let refreshDebounceInterval: TimeInterval = 1.0
}

// MARK: - Data Processing Constants

/// Constants for data processing and storage
enum DataConstants {
    /// Maximum GPS route points to store (for efficiency)
    static let maxRoutePoints: Int = 300

    /// Maximum workouts to display in dashboard
    static let dashboardWorkoutLimit: Int = 100

    /// Days of metrics for baseline calculations
    static let baselineCalculationDays: Int = 7

    /// Days of workouts to include in weekly stats
    static let weeklyStatsDays: Int = 7

    /// Days of recent workouts for coaching context
    static let coachingContextWorkoutDays: Int = 14
}

// MARK: - Rate Limiting Constants

/// Constants for API rate limiting
enum RateLimitConstants {
    /// Requests per minute for OpenRouter API
    static let requestsPerMinute: Double = 10

    /// Burst capacity (max requests without waiting)
    static let burstCapacity: Double = 5

    /// Tokens per second (derived from requests per minute)
    static var tokensPerSecond: Double {
        requestsPerMinute / 60.0
    }
}

// MARK: - Networking Constants

/// Constants for network requests
enum NetworkConstants {
    /// Request timeout (seconds)
    static let requestTimeout: TimeInterval = 120

    /// Resource timeout for streaming (seconds)
    static let resourceTimeout: TimeInterval = 600

    /// Maximum error body to collect (characters)
    static let maxErrorBodyLength: Int = 1000
}

// MARK: - Readiness Score Constants

/// Constants for readiness/wellness scoring
enum ReadinessConstants {
    /// Ideal sleep duration range (hours)
    static let idealSleepMin: Double = 7.0
    static let idealSleepMax: Double = 9.0

    /// Good sleep efficiency threshold
    static let goodSleepEfficiency: Double = 0.9

    /// Ideal deep sleep percentage range
    static let idealDeepSleepMin: Double = 0.15
    static let idealDeepSleepMax: Double = 0.25

    /// VO2 Max trend significance threshold (percent)
    static let vo2MaxTrendThreshold: Double = 2.0

    /// HRV deviation threshold for reduced readiness
    static let hrvDeviationThreshold: Double = 0.15
}

// MARK: - Knowledge Base Constants

/// Constants for RAG knowledge base
enum KnowledgeBaseConstants {
    /// Current knowledge base version
    static let currentVersion: Int = 1

    /// Maximum knowledge documents to retrieve per query
    static let maxRetrievalResults: Int = 5

    /// Knowledge cache validity duration (seconds)
    static let cacheValidityDuration: TimeInterval = 300  // 5 minutes

    /// Minimum relevance score for inclusion
    static let minimumRelevanceScore: Double = 0.3
}
