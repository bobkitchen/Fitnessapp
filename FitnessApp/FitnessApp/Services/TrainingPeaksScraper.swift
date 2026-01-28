import Foundation
import SwiftData

/// Result from parsing a TrainingPeaks shared workout URL
struct TPWorkoutData: Sendable {
    let tss: Double
    let intensityFactor: Double?
    let duration: TimeInterval          // in seconds
    let distance: Double?               // in meters
    let activityType: String            // e.g., "Cycling", "Running", "Swimming"
    let startDate: Date
    let averageHR: Int?
    let averagePower: Int?
    let averagePace: Double?            // seconds per km
    let title: String?
    let routeCoordinates: [(latitude: Double, longitude: Double)]?

    /// Map TP activity type to our ActivityCategory
    var activityCategory: ActivityCategory {
        let type = activityType.lowercased()

        if type.contains("cycling") || type.contains("bike") || type.contains("ride") {
            return .bike
        } else if type.contains("running") || type.contains("run") {
            return .run
        } else if type.contains("swim") {
            return .swim
        } else if type.contains("strength") || type.contains("weight") || type.contains("gym") {
            return .strength
        }
        return .other
    }
}

/// Error types for TP scraping
enum TPScraperError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case parsingError(String)
    case noDataFound
    case unsupportedFormat

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid TrainingPeaks URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingError(let detail):
            return "Parsing error: \(detail)"
        case .noDataFound:
            return "Could not find workout data on the page"
        case .unsupportedFormat:
            return "Unsupported TrainingPeaks page format"
        }
    }
}

/// Service to fetch and parse TrainingPeaks shared workout URLs
actor TrainingPeaksScraper {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        // Create session with delegate to handle HTTP->HTTPS redirect conversion
        self.session = URLSession(configuration: config, delegate: HTTPSRedirectDelegate(), delegateQueue: nil)
    }

    /// Fetch and parse a TrainingPeaks shared workout from URL or pasted text
    /// Accepts either a direct URL or text containing a URL (like from TP share)
    /// - Parameter input: URL string or text containing a TrainingPeaks URL
    /// - Returns: Parsed workout data
    func fetchWorkout(from input: String) async throws -> TPWorkoutData {
        // First, try to extract URL from the input (handles pasted share text)
        let extractionResult = extractURLFromText(input)

        guard let url = extractionResult.url else {
            throw TPScraperError.invalidURL
        }

        // Validate it's a TP URL
        guard isValidTPURL(url) else {
            throw TPScraperError.invalidURL
        }

        // If we extracted metadata from share text, keep it for validation/fallback
        let shareMetadata = extractionResult.metadata

        print("[TPScraper] Extracted URL: \(url.absoluteString)")
        if let metadata = shareMetadata {
            print("[TPScraper] Share text metadata: TSS=\(metadata.tss ?? -1), distance=\(metadata.distance ?? "nil")")
        }

        // Fetch HTML (URLSession follows redirects automatically)
        let html: String
        var finalURL: URL = url

        do {
            // Create a delegate to track redirects
            let (data, response) = try await session.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TPScraperError.networkError(
                    NSError(domain: "HTTP", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                )
            }

            // Track final URL after redirects
            if let responseURL = httpResponse.url {
                finalURL = responseURL
                print("[TPScraper] Final URL after redirects: \(finalURL.absoluteString)")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                throw TPScraperError.networkError(
                    NSError(domain: "HTTP", code: httpResponse.statusCode)
                )
            }

            guard let htmlString = String(data: data, encoding: .utf8) else {
                throw TPScraperError.parsingError("Could not decode HTML")
            }
            html = htmlString
            print("[TPScraper] Fetched \(data.count) bytes of HTML")
        } catch let error as TPScraperError {
            // If network fetch fails but we have share metadata, use it as fallback
            if let metadata = shareMetadata, let tss = metadata.tss {
                print("[TPScraper] Network failed, using share text metadata as fallback")
                return createWorkoutFromShareMetadata(metadata)
            }
            throw error
        } catch {
            // Same fallback for other errors
            if let metadata = shareMetadata, let tss = metadata.tss {
                print("[TPScraper] Network failed, using share text metadata as fallback")
                return createWorkoutFromShareMetadata(metadata)
            }
            throw TPScraperError.networkError(error)
        }

        // Parse the HTML to extract workout data
        do {
            var result = try parseWorkoutHTML(html)

            // If HTML parsing got partial data, supplement with share metadata
            if let metadata = shareMetadata {
                result = mergeWithShareMetadata(result, metadata: metadata)
            }

            return result
        } catch {
            // If HTML parsing fails but we have share metadata, use it
            if let metadata = shareMetadata, let tss = metadata.tss {
                print("[TPScraper] HTML parsing failed, using share text metadata")
                return createWorkoutFromShareMetadata(metadata)
            }
            throw error
        }
    }

    /// Create workout data from share text metadata (fallback)
    private func createWorkoutFromShareMetadata(_ metadata: ShareTextMetadata) -> TPWorkoutData {
        var duration: TimeInterval = 3600  // Default 1 hour

        // Parse duration from string like "0:49:33"
        if let durationStr = metadata.duration {
            duration = parseDurationString(durationStr)
        }

        // Parse distance
        var distanceMeters: Double?
        if let distStr = metadata.distance {
            distanceMeters = parseDistanceString(distStr)
        }

        return TPWorkoutData(
            tss: metadata.tss ?? 0,
            intensityFactor: nil,
            duration: duration,
            distance: distanceMeters,
            activityType: metadata.activityType ?? "Workout",
            startDate: Date(),  // Unknown, use current date
            averageHR: nil,
            averagePower: nil,
            averagePace: nil,
            title: nil,
            routeCoordinates: nil
        )
    }

    /// Merge HTML-parsed data with share metadata
    private func mergeWithShareMetadata(_ data: TPWorkoutData, metadata: ShareTextMetadata) -> TPWorkoutData {
        // Use share metadata to fill in missing fields
        return TPWorkoutData(
            tss: data.tss > 0 ? data.tss : (metadata.tss ?? data.tss),
            intensityFactor: data.intensityFactor,
            duration: data.duration > 0 ? data.duration : (metadata.duration != nil ? parseDurationString(metadata.duration!) : data.duration),
            distance: data.distance ?? (metadata.distance != nil ? parseDistanceString(metadata.distance!) : nil),
            activityType: data.activityType != "Workout" ? data.activityType : (metadata.activityType ?? data.activityType),
            startDate: data.startDate,
            averageHR: data.averageHR,
            averagePower: data.averagePower,
            averagePace: data.averagePace,
            title: data.title,
            routeCoordinates: data.routeCoordinates
        )
    }

    /// Parse duration string like "0:49:33" or "49:33" to seconds
    private func parseDurationString(_ str: String) -> TimeInterval {
        let parts = str.split(separator: ":").compactMap { Int($0) }

        if parts.count == 3 {
            // H:MM:SS
            return Double(parts[0] * 3600 + parts[1] * 60 + parts[2])
        } else if parts.count == 2 {
            // Could be H:MM or MM:SS - assume MM:SS if first part < 10
            if parts[0] < 10 {
                return Double(parts[0] * 3600 + parts[1] * 60)  // H:MM
            } else {
                return Double(parts[0] * 60 + parts[1])  // MM:SS
            }
        }
        return 3600  // Default 1 hour
    }

    /// Parse distance string like "2,215 yds" to meters
    private func parseDistanceString(_ str: String) -> Double? {
        let pattern = #"([\d,]+(?:\.\d+)?)\s*(yds?|yards?|mi(?:les?)?|km|m(?:eters?)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)),
              let numRange = Range(match.range(at: 1), in: str),
              let unitRange = Range(match.range(at: 2), in: str) else {
            return nil
        }

        let numStr = String(str[numRange]).replacingOccurrences(of: ",", with: "")
        let unit = String(str[unitRange]).lowercased()

        guard let value = Double(numStr) else { return nil }

        // Convert to meters
        switch unit {
        case "yd", "yds", "yard", "yards":
            return value * 0.9144
        case "mi", "mile", "miles":
            return value * 1609.34
        case "km":
            return value * 1000
        case "m", "meter", "meters":
            return value
        default:
            return value
        }
    }

    /// Validate that the URL is a TrainingPeaks shared workout URL
    private func isValidTPURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        // Accept various TP URL formats
        let validHosts = [
            "trainingpeaks.com",
            "www.trainingpeaks.com",
            "app.trainingpeaks.com",
            "share.trainingpeaks.com",
            "tpks.ws"  // Short URL format
        ]

        return validHosts.contains(host) || host.hasSuffix(".trainingpeaks.com")
    }

    // MARK: - URL Extraction from Share Text

    /// Metadata extracted from TrainingPeaks share text
    struct ShareTextMetadata {
        let tss: Double?
        let distance: String?
        let duration: String?
        let activityType: String?
    }

    /// Result of extracting URL from input text
    struct URLExtractionResult {
        let url: URL?
        let metadata: ShareTextMetadata?
    }

    /// Convert HTTP URL to HTTPS for App Transport Security compliance
    private func ensureHTTPS(_ urlString: String) -> String {
        if urlString.lowercased().hasPrefix("http://") {
            return "https" + String(urlString.dropFirst(4))  // Replace "http" with "https"
        }
        return urlString
    }

    /// Extract a TrainingPeaks URL from input text
    /// Handles both direct URLs and share text like:
    /// "See my 19 sTSS swim workout. I did 2,215 yds in 0:49:33. http://tpks.ws/XXXXX"
    private func extractURLFromText(_ input: String) -> URLExtractionResult {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // First, try to parse as direct URL
        if let directURL = URL(string: trimmed), isValidTPURL(directURL) {
            // Convert http to https for ATS compliance
            let secureURLString = ensureHTTPS(directURL.absoluteString)
            if let secureURL = URL(string: secureURLString) {
                print("[TPScraper] Direct URL converted: \(trimmed) -> \(secureURLString)")
                return URLExtractionResult(url: secureURL, metadata: nil)
            }
        }

        // Look for URLs in the text using multiple patterns
        let urlPatterns = [
            // http/https URLs
            #"(https?://[^\s]+)"#,
            // tpks.ws short links (may not have http prefix in some contexts)
            #"((?:https?://)?tpks\.ws/[A-Za-z0-9]+)"#,
            // trainingpeaks.com URLs
            #"((?:https?://)?(?:www\.)?trainingpeaks\.com/[^\s]+)"#
        ]

        var extractedURL: URL?

        for pattern in urlPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                if let match = regex.firstMatch(in: trimmed, options: [], range: range),
                   let urlRange = Range(match.range(at: 1), in: trimmed) {
                    var urlString = String(trimmed[urlRange])

                    // Add https:// if missing (use HTTPS for ATS compliance)
                    if !urlString.lowercased().hasPrefix("http") {
                        urlString = "https://" + urlString
                    }

                    // Convert http to https for App Transport Security
                    urlString = ensureHTTPS(urlString)

                    print("[TPScraper] Pattern matched URL: \(urlString)")

                    if let url = URL(string: urlString), isValidTPURL(url) {
                        extractedURL = url
                        break
                    }
                }
            }
        }

        // Try to extract metadata from the share text
        let metadata = parseShareTextMetadata(trimmed)

        return URLExtractionResult(url: extractedURL, metadata: metadata)
    }

    /// Parse metadata from TrainingPeaks share text
    /// Example: "See my 19 sTSS swim workout. I did 2,215 yds in 0:49:33."
    private func parseShareTextMetadata(_ text: String) -> ShareTextMetadata? {
        var tss: Double?
        var distance: String?
        var duration: String?
        var activityType: String?

        let lowerText = text.lowercased()

        // Extract TSS (sTSS, rTSS, TSS)
        let tssPatterns = [
            #"(\d+(?:\.\d+)?)\s*(?:s|r)?tss"#,
            #"(?:s|r)?tss[:\s]*(\d+(?:\.\d+)?)"#
        ]
        for pattern in tssPatterns {
            if let value = extractDouble(from: text, pattern: pattern) {
                tss = value
                break
            }
        }

        // Extract distance (with units)
        let distancePattern = #"([\d,]+(?:\.\d+)?)\s*(yds?|yards?|mi(?:les?)?|km|m(?:eters?)?)"#
        if let regex = try? NSRegularExpression(pattern: distancePattern, options: .caseInsensitive) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                if let numRange = Range(match.range(at: 1), in: text),
                   let unitRange = Range(match.range(at: 2), in: text) {
                    let numStr = String(text[numRange])
                    let unit = String(text[unitRange])
                    distance = "\(numStr) \(unit)"
                }
            }
        }

        // Extract duration (H:MM:SS or M:SS format)
        let durationPattern = #"(\d+:\d{2}(?::\d{2})?)"#
        if let regex = try? NSRegularExpression(pattern: durationPattern, options: []) {
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let durRange = Range(match.range(at: 1), in: text) {
                duration = String(text[durRange])
            }
        }

        // Detect activity type
        if lowerText.contains("swim") {
            activityType = "Swimming"
        } else if lowerText.contains("run") || lowerText.contains("ran") {
            activityType = "Running"
        } else if lowerText.contains("ride") || lowerText.contains("bike") || lowerText.contains("cycling") {
            activityType = "Cycling"
        }

        // Only return metadata if we found something useful
        guard tss != nil || distance != nil || duration != nil || activityType != nil else {
            return nil
        }

        return ShareTextMetadata(
            tss: tss,
            distance: distance,
            duration: duration,
            activityType: activityType
        )
    }

    /// Parse the HTML content to extract workout data
    private func parseWorkoutHTML(_ html: String) throws -> TPWorkoutData {
        // Try multiple parsing strategies

        // Strategy 1: Look for JSON-LD structured data
        if let jsonData = try? extractJSONLD(from: html) {
            return jsonData
        }

        // Strategy 2: Look for inline JavaScript data objects (e.g., publicActivityWrapper)
        if let jsData = try? extractInlineJavaScriptData(from: html) {
            return jsData
        }

        // Strategy 3: Parse HTML directly for workout metrics
        if let parsedData = try? parseHTMLMetrics(from: html) {
            return parsedData
        }

        // Strategy 4: Look for meta tags and Open Graph data
        if let metaData = try? parseMetaTags(from: html) {
            return metaData
        }

        throw TPScraperError.noDataFound
    }

    // MARK: - Parsing Strategies

    /// Extract workout data from JSON-LD structured data if present
    private func extractJSONLD(from html: String) throws -> TPWorkoutData {
        // Look for <script type="application/ld+json">
        let jsonLDPattern = #"<script[^>]*type\s*=\s*[\"']application/ld\+json[\"'][^>]*>([\s\S]*?)</script>"#

        guard let regex = try? NSRegularExpression(pattern: jsonLDPattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)),
              let jsonRange = Range(match.range(at: 1), in: html) else {
            throw TPScraperError.noDataFound
        }

        let jsonString = String(html[jsonRange])
        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw TPScraperError.parsingError("Invalid JSON-LD")
        }

        return try parseJSONWorkout(json)
    }

    /// Extract workout data from inline JavaScript data objects (e.g., publicActivityWrapper)
    private func extractInlineJavaScriptData(from html: String) throws -> TPWorkoutData {
        let objectNames = [
            "publicActivityWrapper",
            "activityData",
            "workoutData",
            "sharedWorkout"
        ]

        for name in objectNames {
            guard let nameRange = html.range(of: name, options: .caseInsensitive) else { continue }

            // Find the first '{' after the object name
            let searchStart = nameRange.upperBound
            guard let braceStart = html[searchStart...].firstIndex(of: "{") else { continue }

            // Extract the JSON object using brace counting
            guard let jsonString = extractBalancedJSON(from: html, startingAt: braceStart) else { continue }

            guard let jsonData = jsonString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else { continue }

            print("[TPScraper] Found inline JS data object '\(name)' with keys: \(json.keys.sorted())")

            // Extract route coordinates from top-level (workoutSampleList may be at top level)
            let topLevelRoute = Self.extractRouteCoordinates(from: json)

            // Try to parse workout data directly from the object
            if let result = try? parseJSONWorkout(json) {
                return result
            }

            // Workout data might be nested under a key
            for (key, value) in json {
                if let nested = value as? [String: Any],
                   nested.keys.contains(where: { $0.lowercased() == "tss" || $0.lowercased() == "if" }),
                   var result = try? parseJSONWorkout(nested) {
                    print("[TPScraper] Found workout data in nested key '\(key)'")
                    // If nested parse didn't find route but top-level had it, merge
                    if result.routeCoordinates == nil, let route = topLevelRoute {
                        result = TPWorkoutData(
                            tss: result.tss,
                            intensityFactor: result.intensityFactor,
                            duration: result.duration,
                            distance: result.distance,
                            activityType: result.activityType,
                            startDate: result.startDate,
                            averageHR: result.averageHR,
                            averagePower: result.averagePower,
                            averagePace: result.averagePace,
                            title: result.title,
                            routeCoordinates: route
                        )
                    }
                    return result
                }
            }
        }

        throw TPScraperError.noDataFound
    }

    /// Extract a balanced JSON object from a string by counting braces
    private func extractBalancedJSON(from string: String, startingAt start: String.Index) -> String? {
        var depth = 0
        var index = start
        var inString = false
        var escaped = false
        var charCount = 0
        let maxChars = 100_000  // Safety limit

        while index < string.endIndex && charCount < maxChars {
            let char = string[index]

            if escaped {
                escaped = false
            } else if char == "\\" && inString {
                escaped = true
            } else if char == "\"" {
                inString = !inString
            } else if !inString {
                if char == "{" {
                    depth += 1
                } else if char == "}" {
                    depth -= 1
                    if depth == 0 {
                        return String(string[start...index])
                    }
                }
            }

            index = string.index(after: index)
            charCount += 1
        }

        return nil
    }

    /// Parse workout metrics directly from HTML
    private func parseHTMLMetrics(from html: String) throws -> TPWorkoutData {
        var tss: Double?
        var intensityFactor: Double?
        var duration: TimeInterval?
        var distance: Double?
        var activityType: String = "Workout"
        var startDate: Date?
        var averageHR: Int?
        var averagePower: Int?
        let averagePace: Double? = nil  // Reserved for future pace parsing
        var title: String?

        // Extract TSS - look for common patterns
        let tssPatterns = [
            #"(?:TSS|Training\s*Stress\s*Score)[:\s]*(\d+(?:\.\d+)?)"#,
            #"\"tss\"[:\s]*(\d+(?:\.\d+)?)"#,
            #"data-tss=\"(\d+(?:\.\d+)?)\""#,
            #"class=\"[^\"]*tss[^\"]*\"[^>]*>(\d+(?:\.\d+)?)"#
        ]

        for pattern in tssPatterns {
            if let value = extractDouble(from: html, pattern: pattern) {
                tss = value
                break
            }
        }

        // Extract Intensity Factor
        let ifPatterns = [
            #"(?:IF|Intensity\s*Factor)[:\s]*(\d+(?:\.\d+)?)"#,
            #"\"intensityFactor\"[:\s]*(\d+(?:\.\d+)?)"#,
            #"\"if\"[:\s]*(\d+(?:\.\d+)?)"#
        ]

        for pattern in ifPatterns {
            if let value = extractDouble(from: html, pattern: pattern) {
                intensityFactor = value
                break
            }
        }

        // Extract Duration - look for various formats
        let durationPatterns = [
            #"(?:Duration|Time)[:\s]*(\d+):(\d+):(\d+)"#,        // HH:MM:SS
            #"(?:Duration|Time)[:\s]*(\d+):(\d+)"#,              // MM:SS or H:MM
            #"\"duration\"[:\s]*(\d+)"#,                          // seconds
            #"\"durationSeconds\"[:\s]*(\d+)"#
        ]

        // Try HH:MM:SS format first
        if let regex = try? NSRegularExpression(pattern: durationPatterns[0], options: .caseInsensitive),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)) {
            if let h = Int(extractGroup(from: html, match: match, group: 1) ?? ""),
               let m = Int(extractGroup(from: html, match: match, group: 2) ?? ""),
               let s = Int(extractGroup(from: html, match: match, group: 3) ?? "") {
                duration = Double(h * 3600 + m * 60 + s)
            }
        }

        // Try MM:SS format
        if duration == nil, let regex = try? NSRegularExpression(pattern: durationPatterns[1], options: .caseInsensitive),
           let match = regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)) {
            if let first = Int(extractGroup(from: html, match: match, group: 1) ?? ""),
               let second = Int(extractGroup(from: html, match: match, group: 2) ?? "") {
                // Determine if it's H:MM or MM:SS based on magnitude
                if first > 60 || second > 59 {
                    duration = Double(first * 60 + second) // Probably M:SS with large minutes
                } else if first < 10 {
                    duration = Double(first * 3600 + second * 60) // Probably H:MM
                } else {
                    duration = Double(first * 60 + second) // MM:SS
                }
            }
        }

        // Try seconds format
        if duration == nil {
            for pattern in durationPatterns[2...] {
                if let value = extractDouble(from: html, pattern: pattern) {
                    duration = value
                    break
                }
            }
        }

        // Extract Distance
        let distancePatterns = [
            #"(?:Distance)[:\s]*(\d+(?:\.\d+)?)\s*(?:km|kilometers)"#,
            #"(?:Distance)[:\s]*(\d+(?:\.\d+)?)\s*(?:mi|miles)"#,
            #"(?:Distance)[:\s]*(\d+(?:\.\d+)?)\s*(?:m|meters)"#,
            #"\"distance\"[:\s]*(\d+(?:\.\d+)?)"#,
            #"\"distanceMeters\"[:\s]*(\d+(?:\.\d+)?)"#
        ]

        for (index, pattern) in distancePatterns.enumerated() {
            if let value = extractDouble(from: html, pattern: pattern) {
                switch index {
                case 0: distance = value * 1000    // km to meters
                case 1: distance = value * 1609.34 // miles to meters
                default: distance = value          // already meters or needs no conversion
                }
                break
            }
        }

        // Extract Activity Type
        let activityPatterns = [
            #"(?:Activity|Type|Sport)[:\s]*([A-Za-z]+(?:\s+[A-Za-z]+)?)"#,
            #"\"activityType\"[:\s]*\"([^\"]+)\""#,
            #"\"sport\"[:\s]*\"([^\"]+)\""#,
            #"<title>([^<]*(?:Run|Ride|Swim|Bike|Cycle)[^<]*)</title>"#
        ]

        for pattern in activityPatterns {
            if let value = extractString(from: html, pattern: pattern) {
                activityType = value
                break
            }
        }

        // Extract Start Date
        let datePatterns = [
            #"\"startTime\"[:\s]*\"([^\"]+)\""#,
            #"\"startDate\"[:\s]*\"([^\"]+)\""#,
            #"(?:Date|Started)[:\s]*(\d{4}-\d{2}-\d{2})"#,
            #"datetime=\"([^\"]+)\""#
        ]

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        for pattern in datePatterns {
            if let dateString = extractString(from: html, pattern: pattern) {
                if let date = isoFormatter.date(from: dateString) {
                    startDate = date
                    break
                } else if let date = dateFormatter.date(from: dateString) {
                    startDate = date
                    break
                }
            }
        }

        // Extract Average HR
        let hrPatterns = [
            #"(?:Avg|Average)\s*(?:HR|Heart\s*Rate)[:\s]*(\d+)"#,
            #"\"averageHeartRate\"[:\s]*(\d+)"#,
            #"\"avgHr\"[:\s]*(\d+)"#
        ]

        for pattern in hrPatterns {
            if let value = extractDouble(from: html, pattern: pattern) {
                averageHR = Int(value)
                break
            }
        }

        // Extract Average Power
        let powerPatterns = [
            #"(?:Avg|Average)\s*(?:Power)[:\s]*(\d+)"#,
            #"(?:NP|Normalized\s*Power)[:\s]*(\d+)"#,
            #"\"averagePower\"[:\s]*(\d+)"#,
            #"\"normalizedPower\"[:\s]*(\d+)"#
        ]

        for pattern in powerPatterns {
            if let value = extractDouble(from: html, pattern: pattern) {
                averagePower = Int(value)
                break
            }
        }

        // Extract Title
        let titlePatterns = [
            #"<title>([^<]+)</title>"#,
            #"\"title\"[:\s]*\"([^\"]+)\""#,
            #"\"name\"[:\s]*\"([^\"]+)\""#
        ]

        for pattern in titlePatterns {
            if let value = extractString(from: html, pattern: pattern) {
                title = value.trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        // Validate we got minimum required data
        guard let extractedTSS = tss, let extractedDuration = duration else {
            throw TPScraperError.noDataFound
        }

        return TPWorkoutData(
            tss: extractedTSS,
            intensityFactor: intensityFactor,
            duration: extractedDuration,
            distance: distance,
            activityType: activityType,
            startDate: startDate ?? Date(),
            averageHR: averageHR,
            averagePower: averagePower,
            averagePace: averagePace,
            title: title,
            routeCoordinates: nil
        )
    }

    /// Parse Open Graph and meta tags for workout data
    private func parseMetaTags(from html: String) throws -> TPWorkoutData {
        // Look for og:description or similar meta tags that might contain workout summary
        let metaPattern = #"<meta[^>]+(?:name|property)=\"([^\"]+)\"[^>]+content=\"([^\"]+)\""#

        guard let regex = try? NSRegularExpression(pattern: metaPattern, options: .caseInsensitive) else {
            throw TPScraperError.noDataFound
        }

        var metaData: [String: String] = [:]
        let matches = regex.matches(in: html, options: [], range: NSRange(html.startIndex..., in: html))

        for match in matches {
            if let nameRange = Range(match.range(at: 1), in: html),
               let contentRange = Range(match.range(at: 2), in: html) {
                let name = String(html[nameRange]).lowercased()
                let content = String(html[contentRange])
                metaData[name] = content
            }
        }

        // Try to parse description for workout data
        guard let description = metaData["og:description"] ?? metaData["description"] else {
            throw TPScraperError.noDataFound
        }

        // Parse TSS from description - handle both "TSS: 123" and "123 sTSS" formats
        let tssPatterns = [
            #"(\d+(?:\.\d+)?)\s*(?:s|r)?TSS"#,      // "18.8 sTSS" or "19 rTSS"
            #"TSS[:\s]*(\d+(?:\.\d+)?)"#,            // "TSS: 123"
            #"with\s+(\d+(?:\.\d+)?)\s*(?:s|r)?TSS"# // "with 18.8 sTSS"
        ]

        var tss: Double?
        for pattern in tssPatterns {
            if let value = extractDouble(from: description, pattern: pattern) {
                tss = value
                break
            }
        }

        guard let extractedTSS = tss else {
            throw TPScraperError.noDataFound
        }

        // Try to get duration - handle "0:49:32" format
        var duration: TimeInterval = 3600 // default 1 hour if not found

        // Try HH:MM:SS or H:MM:SS format first (most common in TP)
        if let regex = try? NSRegularExpression(pattern: #"(\d+):(\d{2}):(\d{2})"#, options: []),
           let match = regex.firstMatch(in: description, options: [], range: NSRange(description.startIndex..., in: description)) {
            if let hRange = Range(match.range(at: 1), in: description),
               let mRange = Range(match.range(at: 2), in: description),
               let sRange = Range(match.range(at: 3), in: description),
               let h = Int(description[hRange]),
               let m = Int(description[mRange]),
               let s = Int(description[sRange]) {
                duration = Double(h * 3600 + m * 60 + s)
            }
        } else if let durationMatch = extractDouble(from: description, pattern: #"(\d+(?:\.\d+)?)\s*(?:hr|hour)"#) {
            duration = durationMatch * 3600
        } else if let durationMatch = extractDouble(from: description, pattern: #"(\d+)\s*(?:min)"#) {
            duration = durationMatch * 60
        }

        // Extract distance
        var distance: Double?
        let distancePatterns = [
            (#"([\d,]+(?:\.\d+)?)\s*(?:yd|yard)"#, 0.9144),      // yards to meters
            (#"([\d,]+(?:\.\d+)?)\s*(?:mi|mile)"#, 1609.34),     // miles to meters
            (#"([\d,]+(?:\.\d+)?)\s*(?:km)"#, 1000.0),           // km to meters
            (#"([\d,]+(?:\.\d+)?)\s*(?:m|meter)"#, 1.0)          // already meters
        ]

        for (pattern, multiplier) in distancePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: description, options: [], range: NSRange(description.startIndex..., in: description)),
               let range = Range(match.range(at: 1), in: description) {
                let numStr = String(description[range]).replacingOccurrences(of: ",", with: "")
                if let value = Double(numStr) {
                    distance = value * multiplier
                    break
                }
            }
        }

        // Extract date and time
        // First try: look for ISO datetime strings in the full HTML (e.g. from embedded JSON)
        var workoutDate = Date()
        let dateTimePatterns = [
            #"\"startTime\"[:\s]*\"([^\"]+)\""#,
            #"\"startDate\"[:\s]*\"([^\"]+)\""#,
            #"\"completedDate\"[:\s]*\"([^\"]+)\""#,
            #"\"workoutDay\"[:\s]*\"([^\"]+)\""#,
            #"datetime=\"([^\"]+)\""#
        ]
        let isoFormatter = ISO8601DateFormatter()
        var foundDateTime = false
        for pattern in dateTimePatterns {
            if let dateString = extractString(from: html, pattern: pattern) {
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = isoFormatter.date(from: dateString) {
                    workoutDate = date
                    foundDateTime = true
                    break
                }
                isoFormatter.formatOptions = [.withInternetDateTime]
                if let date = isoFormatter.date(from: dateString) {
                    workoutDate = date
                    foundDateTime = true
                    break
                }
            }
        }
        // Fallback: extract date from description (format: "on 1/25" or "on 01/25") — no time info
        if !foundDateTime {
            if let regex = try? NSRegularExpression(pattern: #"on\s+(\d{1,2})/(\d{1,2})"#, options: []),
               let match = regex.firstMatch(in: description, options: [], range: NSRange(description.startIndex..., in: description)),
               let monthRange = Range(match.range(at: 1), in: description),
               let dayRange = Range(match.range(at: 2), in: description),
               let month = Int(description[monthRange]),
               let day = Int(description[dayRange]) {
                var components = Calendar.current.dateComponents([.year], from: Date())
                components.month = month
                components.day = day
                if let date = Calendar.current.date(from: components) {
                    workoutDate = date
                }
            }
        }

        // Extract IF from description or full HTML
        var intensityFactor: Double?
        let ifPatterns = [
            #"(?:IF)[:\s]*(\d+(?:\.\d+)?)"#,
            #"(\d+\.\d+)\s*IF\b"#,
            #"\"intensityFactor\"[:\s]*(\d+(?:\.\d+)?)"#,
            #"\"if\"[:\s]*(\d+(?:\.\d+)?)"#
        ]
        // Try description first, then full HTML for IF
        for pattern in ifPatterns {
            if let value = extractDouble(from: description, pattern: pattern), value > 0, value <= 2.0 {
                intensityFactor = value
                break
            }
        }
        if intensityFactor == nil {
            for pattern in ifPatterns {
                if let value = extractDouble(from: html, pattern: pattern), value > 0, value <= 2.0 {
                    intensityFactor = value
                    break
                }
            }
        }

        // Try to determine activity type from title or description
        let title = metaData["og:title"] ?? ""
        var activityType = "Workout"

        if title.lowercased().contains("run") || description.lowercased().contains("run") {
            activityType = "Running"
        } else if title.lowercased().contains("ride") || title.lowercased().contains("bike") ||
                  description.lowercased().contains("ride") || description.lowercased().contains("cycling") {
            activityType = "Cycling"
        } else if title.lowercased().contains("swim") || description.lowercased().contains("swim") {
            activityType = "Swimming"
        }

        print("[TPScraper] Parsed from meta tags: TSS=\(extractedTSS), IF=\(intensityFactor ?? -1), duration=\(duration)s, distance=\(distance ?? 0)m, date=\(workoutDate)")

        return TPWorkoutData(
            tss: extractedTSS,
            intensityFactor: intensityFactor,
            duration: duration,
            distance: distance,
            activityType: activityType,
            startDate: workoutDate,
            averageHR: nil,
            averagePower: nil,
            averagePace: nil,
            title: title.isEmpty ? nil : title,
            routeCoordinates: nil
        )
    }

    /// Parse JSON workout data structure
    private func parseJSONWorkout(_ json: [String: Any]) throws -> TPWorkoutData {
        // TSS can appear under various keys depending on sport type
        guard let tss = jsonDouble(json, keys: ["tss", "trainingStressScore", "sTss", "rTss", "hrTss"]) else {
            throw TPScraperError.parsingError("No TSS in JSON")
        }

        let duration = jsonDouble(json, keys: ["duration", "durationSeconds", "movingTime"]) ?? 3600

        let activityType = jsonString(json, keys: ["activityType", "sport", "type"]) ?? "Workout"

        var startDate = Date()
        if let dateString = jsonString(json, keys: ["startTime", "startDate", "workoutDay", "completedDate"]) {
            let formatter = ISO8601DateFormatter()
            // Try with fractional seconds first, then without
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateString) {
                startDate = date
            } else {
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateString) {
                    startDate = date
                }
            }
        }

        let intensityFactor = jsonDouble(json, keys: ["intensityFactor", "if"])
        let distance = jsonDouble(json, keys: ["distance", "distanceMeters"])
        let avgHR = jsonDouble(json, keys: ["averageHeartRate", "avgHr", "heartRateAverage"])
        let avgPower = jsonDouble(json, keys: ["averagePower", "normalizedPower", "avgPower"])
        let avgPace = jsonDouble(json, keys: ["averagePace"])

        // Extract GPS route from workoutSampleList
        let routeCoordinates = Self.extractRouteCoordinates(from: json)

        return TPWorkoutData(
            tss: tss,
            intensityFactor: intensityFactor,
            duration: duration,
            distance: distance,
            activityType: activityType,
            startDate: startDate,
            averageHR: avgHR.map { Int($0) },
            averagePower: avgPower.map { Int($0) },
            averagePace: avgPace,
            title: jsonString(json, keys: ["title", "name"]),
            routeCoordinates: routeCoordinates
        )
    }

    /// Extract GPS route coordinates from a JSON dictionary containing workoutSampleList
    /// Each sample has values array: [cadence, elevation, speed, power, heartRate, distance, positionLat, positionLong]
    private static func extractRouteCoordinates(from json: [String: Any]) -> [(latitude: Double, longitude: Double)]? {
        guard let samples = json["workoutSampleList"] as? [[String: Any]] else { return nil }

        var coords: [(latitude: Double, longitude: Double)] = []
        for sample in samples {
            guard let values = sample["values"] as? [Any], values.count >= 8 else { continue }
            let lat: Double?
            let lng: Double?
            if let d = values[6] as? Double { lat = d }
            else if let n = values[6] as? NSNumber { lat = n.doubleValue }
            else { lat = nil }
            if let d = values[7] as? Double { lng = d }
            else if let n = values[7] as? NSNumber { lng = n.doubleValue }
            else { lng = nil }
            guard let latitude = lat, let longitude = lng,
                  latitude != 0, longitude != 0 else { continue }
            coords.append((latitude, longitude))
        }
        return coords.isEmpty ? nil : coords
    }

    /// Safely extract a Double from a JSON dictionary, trying multiple keys.
    /// Handles both Double and Int JSON number types.
    /// Uses case-insensitive key matching to handle varying TP JSON casing (e.g. "sTSS" vs "sTss").
    private func jsonDouble(_ json: [String: Any], keys: [String]) -> Double? {
        // First try exact key match (fast path)
        for key in keys {
            if let value = json[key] as? Double {
                return value
            }
            if let value = json[key] as? Int {
                return Double(value)
            }
            if let value = json[key] as? NSNumber {
                return value.doubleValue
            }
        }
        // Fall back to case-insensitive key match
        let lowercasedKeys = keys.map { $0.lowercased() }
        for (jsonKey, jsonValue) in json {
            let lk = jsonKey.lowercased()
            if lowercasedKeys.contains(lk) {
                if let value = jsonValue as? Double { return value }
                if let value = jsonValue as? Int { return Double(value) }
                if let value = jsonValue as? NSNumber { return value.doubleValue }
            }
        }
        return nil
    }

    /// Safely extract a String from a JSON dictionary, trying multiple keys with case-insensitive matching.
    private func jsonString(_ json: [String: Any], keys: [String]) -> String? {
        // Exact match first
        for key in keys {
            if let value = json[key] as? String {
                return value
            }
        }
        // Case-insensitive fallback
        let lowercasedKeys = keys.map { $0.lowercased() }
        for (jsonKey, jsonValue) in json {
            if lowercasedKeys.contains(jsonKey.lowercased()),
               let value = jsonValue as? String {
                return value
            }
        }
        return nil
    }

    // MARK: - Regex Helpers

    private func extractDouble(from text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[range])
    }

    private func extractString(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private func extractGroup(from text: String, match: NSTextCheckingResult, group: Int) -> String? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return String(text[range])
    }
}

// MARK: - HTTPS Redirect Delegate

/// URLSession delegate that converts HTTP redirects to HTTPS for ATS compliance
final class HTTPSRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var modifiedRequest = request

        // If redirect URL is HTTP, convert to HTTPS
        if let url = request.url, url.scheme == "http" {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.scheme = "https"
            if let httpsURL = components?.url {
                modifiedRequest = URLRequest(url: httpsURL)
                print("[TPScraper] Converted redirect from HTTP to HTTPS: \(httpsURL)")
            }
        }

        completionHandler(modifiedRequest)
    }
}
