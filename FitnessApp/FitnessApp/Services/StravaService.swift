//
//  StravaService.swift
//  FitnessApp
//
//  Strava API integration for workout sync with routes and titles.
//  Uses OAuth 2.0 for authentication.
//

import Foundation
import AuthenticationServices
import SwiftUI

// MARK: - Strava Service

@Observable
@MainActor
final class StravaService: NSObject {

    // MARK: - Configuration

    /// Strava API credentials - these should be set from your Strava API application
    /// Get yours at: https://www.strava.com/settings/api
    private static let clientId = "YOUR_CLIENT_ID"  // TODO: Replace with actual client ID
    private static let clientSecret = "YOUR_CLIENT_SECRET"  // TODO: Replace with actual client secret
    private static let redirectUri = "fitnesscoach://strava"
    private static let scope = "activity:read_all"

    private static let authURL = "https://www.strava.com/oauth/authorize"
    private static let tokenURL = "https://www.strava.com/oauth/token"
    private static let apiBaseURL = "https://www.strava.com/api/v3"

    // MARK: - State

    var isAuthenticated: Bool = false
    var isAuthenticating: Bool = false
    var athleteProfile: StravaAthlete?
    var lastSyncDate: Date?
    var syncError: String?

    private var webAuthSession: ASWebAuthenticationSession?
    private var presentationAnchor: ASPresentationAnchor?

    // MARK: - Initialization

    override init() {
        super.init()
        checkAuthentication()
    }

    // MARK: - Authentication

    /// Check if we have valid tokens stored
    func checkAuthentication() {
        if let _ = StravaTokenManager.getAccessToken() {
            isAuthenticated = true
            // Load cached athlete profile
            athleteProfile = StravaTokenManager.getAthleteProfile()
        } else {
            isAuthenticated = false
        }
    }

    /// Start OAuth flow
    func authenticate(presentationAnchor: ASPresentationAnchor) async throws {
        self.presentationAnchor = presentationAnchor
        isAuthenticating = true
        syncError = nil

        defer { isAuthenticating = false }

        // Build authorization URL
        var components = URLComponents(string: Self.authURL)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: Self.clientId),
            URLQueryItem(name: "redirect_uri", value: Self.redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "approval_prompt", value: "auto")
        ]

        guard let authURL = components.url else {
            throw StravaError.invalidURL
        }

        // Use ASWebAuthenticationSession for OAuth
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "fitnesscoach"
            ) { callbackURL, error in
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        continuation.resume(throwing: StravaError.userCancelled)
                    } else {
                        continuation.resume(throwing: StravaError.authenticationFailed(error.localizedDescription))
                    }
                    return
                }

                guard let url = callbackURL else {
                    continuation.resume(throwing: StravaError.noCallbackURL)
                    return
                }

                continuation.resume(returning: url)
            }

            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false

            self.webAuthSession = session

            if !session.start() {
                continuation.resume(throwing: StravaError.sessionStartFailed)
            }
        }

        // Extract authorization code from callback
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw StravaError.noAuthorizationCode
        }

        // Exchange code for tokens
        try await exchangeCodeForTokens(code: code)

        isAuthenticated = true
        print("[Strava] Authentication successful")
    }

    /// Exchange authorization code for access/refresh tokens
    private func exchangeCodeForTokens(code: String) async throws {
        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "client_id": Self.clientId,
            "client_secret": Self.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StravaError.tokenExchangeFailed
        }

        let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)

        // Save tokens
        try StravaTokenManager.saveTokens(tokenResponse)

        // Save athlete profile
        athleteProfile = tokenResponse.athlete
        if let athlete = tokenResponse.athlete {
            StravaTokenManager.saveAthleteProfile(athlete)
        }
    }

    /// Refresh access token using refresh token
    func refreshTokenIfNeeded() async throws {
        guard let expiresAt = StravaTokenManager.getTokenExpiry(),
              expiresAt < Date() else {
            return // Token still valid
        }

        guard let refreshToken = StravaTokenManager.getRefreshToken() else {
            throw StravaError.noRefreshToken
        }

        var request = URLRequest(url: URL(string: Self.tokenURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "client_id": Self.clientId,
            "client_secret": Self.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            // Refresh failed - need to re-authenticate
            logout()
            throw StravaError.tokenRefreshFailed
        }

        let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        try StravaTokenManager.saveTokens(tokenResponse)

        print("[Strava] Token refreshed successfully")
    }

    /// Sign out and clear tokens
    func logout() {
        StravaTokenManager.clearTokens()
        isAuthenticated = false
        athleteProfile = nil
        lastSyncDate = nil
    }

    // MARK: - API Calls

    /// Fetch recent activities from Strava
    func fetchActivities(after: Date? = nil, perPage: Int = 30) async throws -> [StravaActivity] {
        try await refreshTokenIfNeeded()

        guard let accessToken = StravaTokenManager.getAccessToken() else {
            throw StravaError.notAuthenticated
        }

        var components = URLComponents(string: "\(Self.apiBaseURL)/athlete/activities")!
        var queryItems = [
            URLQueryItem(name: "per_page", value: String(perPage))
        ]

        if let after = after {
            queryItems.append(URLQueryItem(name: "after", value: String(Int(after.timeIntervalSince1970))))
        }

        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StravaError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            // Token expired during request
            logout()
            throw StravaError.notAuthenticated
        }

        guard httpResponse.statusCode == 200 else {
            throw StravaError.apiError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let activities = try decoder.decode([StravaActivity].self, from: data)

        lastSyncDate = Date()
        print("[Strava] Fetched \(activities.count) activities")

        return activities
    }

    /// Fetch detailed activity with streams (for route data)
    func fetchActivityDetail(id: Int) async throws -> StravaActivityDetail {
        try await refreshTokenIfNeeded()

        guard let accessToken = StravaTokenManager.getAccessToken() else {
            throw StravaError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "\(Self.apiBaseURL)/activities/\(id)")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StravaError.apiError((response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        return try decoder.decode(StravaActivityDetail.self, from: data)
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension StravaService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationAnchor ?? ASPresentationAnchor()
    }
}

// MARK: - Strava Token Manager

enum StravaTokenManager {

    private static let accessTokenKey = "com.bobk.FitnessApp.strava.accessToken"
    private static let refreshTokenKey = "com.bobk.FitnessApp.strava.refreshToken"
    private static let expiryKey = "com.bobk.FitnessApp.strava.expiry"
    private static let athleteKey = "com.bobk.FitnessApp.strava.athlete"

    static func saveTokens(_ response: StravaTokenResponse) throws {
        // Save access token to Keychain
        let accessQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: accessTokenKey,
            kSecValueData as String: response.accessToken.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(accessQuery as CFDictionary)
        let accessStatus = SecItemAdd(accessQuery as CFDictionary, nil)
        guard accessStatus == errSecSuccess else {
            throw StravaError.keychainError
        }

        // Save refresh token to Keychain
        let refreshQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: refreshTokenKey,
            kSecValueData as String: response.refreshToken.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(refreshQuery as CFDictionary)
        let refreshStatus = SecItemAdd(refreshQuery as CFDictionary, nil)
        guard refreshStatus == errSecSuccess else {
            throw StravaError.keychainError
        }

        // Save expiry to UserDefaults (not sensitive)
        UserDefaults.standard.set(response.expiresAt, forKey: expiryKey)
    }

    static func getAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: accessTokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    static func getRefreshToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: refreshTokenKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    static func getTokenExpiry() -> Date? {
        let timestamp = UserDefaults.standard.integer(forKey: expiryKey)
        guard timestamp > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    static func saveAthleteProfile(_ athlete: StravaAthlete) {
        if let data = try? JSONEncoder().encode(athlete) {
            UserDefaults.standard.set(data, forKey: athleteKey)
        }
    }

    static func getAthleteProfile() -> StravaAthlete? {
        guard let data = UserDefaults.standard.data(forKey: athleteKey) else { return nil }
        return try? JSONDecoder().decode(StravaAthlete.self, from: data)
    }

    static func clearTokens() {
        // Delete from Keychain
        let accessQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: accessTokenKey
        ]
        SecItemDelete(accessQuery as CFDictionary)

        let refreshQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: refreshTokenKey
        ]
        SecItemDelete(refreshQuery as CFDictionary)

        // Clear UserDefaults
        UserDefaults.standard.removeObject(forKey: expiryKey)
        UserDefaults.standard.removeObject(forKey: athleteKey)
    }
}

// MARK: - Strava Errors

enum StravaError: LocalizedError {
    case invalidURL
    case userCancelled
    case authenticationFailed(String)
    case noCallbackURL
    case sessionStartFailed
    case noAuthorizationCode
    case tokenExchangeFailed
    case tokenRefreshFailed
    case noRefreshToken
    case notAuthenticated
    case invalidResponse
    case apiError(Int)
    case keychainError
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Strava URL"
        case .userCancelled:
            return "Authentication cancelled"
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .noCallbackURL:
            return "No callback URL received"
        case .sessionStartFailed:
            return "Could not start authentication session"
        case .noAuthorizationCode:
            return "No authorization code in callback"
        case .tokenExchangeFailed:
            return "Failed to exchange code for tokens"
        case .tokenRefreshFailed:
            return "Failed to refresh access token"
        case .noRefreshToken:
            return "No refresh token available"
        case .notAuthenticated:
            return "Not authenticated with Strava"
        case .invalidResponse:
            return "Invalid response from Strava"
        case .apiError(let code):
            return "Strava API error (HTTP \(code))"
        case .keychainError:
            return "Failed to save credentials securely"
        case .decodingError:
            return "Failed to decode Strava response"
        }
    }
}

// MARK: - Strava API Models

struct StravaTokenResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Int
    let athlete: StravaAthlete?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case athlete
    }
}

struct StravaAthlete: Codable {
    let id: Int
    let firstName: String?
    let lastName: String?
    let profileMedium: String?
    let city: String?
    let country: String?

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "firstname"
        case lastName = "lastname"
        case profileMedium = "profile_medium"
        case city
        case country
    }

    var fullName: String {
        [firstName, lastName].compactMap { $0 }.joined(separator: " ")
    }
}

struct StravaActivity: Codable, Identifiable {
    let id: Int
    let name: String
    let type: String
    let sportType: String?
    let startDate: Date
    let startDateLocal: Date
    let timezone: String?
    let movingTime: Int
    let elapsedTime: Int
    let distance: Double
    let totalElevationGain: Double?
    let averageSpeed: Double?
    let maxSpeed: Double?
    let averageHeartrate: Double?
    let maxHeartrate: Double?
    let averageWatts: Double?
    let maxWatts: Int?
    let weightedAverageWatts: Int?  // Normalized Power
    let kilojoules: Double?
    let averageCadence: Double?
    let map: StravaMap?
    let trainer: Bool?
    let commute: Bool?
    let manual: Bool?
    let deviceWatts: Bool?
    let sufferScore: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, type, timezone, distance, map, trainer, commute, manual
        case sportType = "sport_type"
        case startDate = "start_date"
        case startDateLocal = "start_date_local"
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case averageSpeed = "average_speed"
        case maxSpeed = "max_speed"
        case averageHeartrate = "average_heartrate"
        case maxHeartrate = "max_heartrate"
        case averageWatts = "average_watts"
        case maxWatts = "max_watts"
        case weightedAverageWatts = "weighted_average_watts"
        case kilojoules
        case averageCadence = "average_cadence"
        case deviceWatts = "device_watts"
        case sufferScore = "suffer_score"
    }

    /// Map Strava activity type to our ActivityCategory
    var activityCategory: ActivityCategory {
        let lowerType = type.lowercased()
        switch lowerType {
        case "ride", "virtualride", "ebikeride", "handcycle", "velomobile":
            return .bike
        case "run", "virtualrun", "trailrun":
            return .run
        case "swim":
            return .swim
        case "weighttraining", "crossfit", "workout":
            return .strength
        default:
            return .other
        }
    }

    /// Duration in seconds
    var durationSeconds: Double {
        Double(movingTime)
    }

    /// Distance in meters
    var distanceMeters: Double {
        distance
    }
}

struct StravaMap: Codable {
    let id: String
    let summaryPolyline: String?
    let polyline: String?

    enum CodingKeys: String, CodingKey {
        case id
        case summaryPolyline = "summary_polyline"
        case polyline
    }
}

struct StravaActivityDetail: Codable {
    let id: Int
    let name: String
    let description: String?
    let type: String
    let startDate: Date
    let movingTime: Int
    let elapsedTime: Int
    let distance: Double
    let totalElevationGain: Double?
    let map: StravaMap?
    let calories: Double?
    let segmentEfforts: [StravaSegmentEffort]?
    let splitsMetric: [StravaSplit]?
    let laps: [StravaLap]?
    let gear: StravaGear?
    let deviceName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, type, distance, map, calories, gear
        case startDate = "start_date"
        case movingTime = "moving_time"
        case elapsedTime = "elapsed_time"
        case totalElevationGain = "total_elevation_gain"
        case segmentEfforts = "segment_efforts"
        case splitsMetric = "splits_metric"
        case laps
        case deviceName = "device_name"
    }
}

struct StravaSegmentEffort: Codable {
    let id: Int
    let name: String
    let elapsedTime: Int
    let movingTime: Int
    let distance: Double
    let prRank: Int?
    let komRank: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, distance
        case elapsedTime = "elapsed_time"
        case movingTime = "moving_time"
        case prRank = "pr_rank"
        case komRank = "kom_rank"
    }
}

struct StravaSplit: Codable {
    let distance: Double
    let elapsedTime: Int
    let movingTime: Int
    let averageSpeed: Double
    let averageHeartrate: Double?
    let paceZone: Int?

    enum CodingKeys: String, CodingKey {
        case distance
        case elapsedTime = "elapsed_time"
        case movingTime = "moving_time"
        case averageSpeed = "average_speed"
        case averageHeartrate = "average_heartrate"
        case paceZone = "pace_zone"
    }
}

struct StravaLap: Codable {
    let id: Int
    let name: String
    let elapsedTime: Int
    let movingTime: Int
    let distance: Double
    let averageSpeed: Double
    let averageHeartrate: Double?
    let averageWatts: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, distance
        case elapsedTime = "elapsed_time"
        case movingTime = "moving_time"
        case averageSpeed = "average_speed"
        case averageHeartrate = "average_heartrate"
        case averageWatts = "average_watts"
    }
}

struct StravaGear: Codable {
    let id: String
    let name: String
    let distance: Double
}
