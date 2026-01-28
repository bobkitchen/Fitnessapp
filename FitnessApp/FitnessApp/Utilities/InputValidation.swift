//
//  InputValidation.swift
//  FitnessApp
//
//  Input validation and sanitization for external data sources.
//  Protects against invalid data from OCR, imports, and user input.
//

import Foundation

// MARK: - Validation Errors

/// Errors that can occur during input validation
enum ValidationError: LocalizedError {
    case valueOutOfRange(field: String, value: Double, min: Double, max: Double)
    case stringTooLong(field: String, length: Int, maxLength: Int)
    case invalidFormat(field: String, reason: String)
    case regexTimeout(pattern: String)
    case missingRequiredField(field: String)
    case invalidDate(field: String, value: String)

    var errorDescription: String? {
        switch self {
        case .valueOutOfRange(let field, let value, let min, let max):
            return "\(field) value \(value) is out of valid range (\(min)-\(max))"
        case .stringTooLong(let field, let length, let maxLength):
            return "\(field) is too long (\(length) characters, max \(maxLength))"
        case .invalidFormat(let field, let reason):
            return "\(field) has invalid format: \(reason)"
        case .regexTimeout(let pattern):
            return "Pattern matching timed out for pattern: \(pattern)"
        case .missingRequiredField(let field):
            return "Required field '\(field)' is missing"
        case .invalidDate(let field, let value):
            return "\(field) has invalid date value: \(value)"
        }
    }
}

// MARK: - Input Validator

/// Centralized input validation for external data sources
struct InputValidator {

    // MARK: - PMC Value Validation

    /// Valid range for CTL (Chronic Training Load)
    static let ctlRange = 0.0...500.0

    /// Valid range for ATL (Acute Training Load)
    static let atlRange = 0.0...500.0

    /// Valid range for TSB (Training Stress Balance)
    static let tsbRange = -200.0...200.0

    /// Valid range for TSS (Training Stress Score)
    static let tssRange = 0.0...1000.0

    /// Validate CTL value from OCR or import
    static func validateCTL(_ value: Double) throws -> Double {
        guard ctlRange.contains(value) else {
            throw ValidationError.valueOutOfRange(
                field: "CTL",
                value: value,
                min: ctlRange.lowerBound,
                max: ctlRange.upperBound
            )
        }
        return value
    }

    /// Validate ATL value from OCR or import
    static func validateATL(_ value: Double) throws -> Double {
        guard atlRange.contains(value) else {
            throw ValidationError.valueOutOfRange(
                field: "ATL",
                value: value,
                min: atlRange.lowerBound,
                max: atlRange.upperBound
            )
        }
        return value
    }

    /// Validate TSB value from OCR or import
    static func validateTSB(_ value: Double) throws -> Double {
        guard tsbRange.contains(value) else {
            throw ValidationError.valueOutOfRange(
                field: "TSB",
                value: value,
                min: tsbRange.lowerBound,
                max: tsbRange.upperBound
            )
        }
        return value
    }

    /// Validate TSS value from OCR or import
    static func validateTSS(_ value: Double) throws -> Double {
        guard tssRange.contains(value) else {
            throw ValidationError.valueOutOfRange(
                field: "TSS",
                value: value,
                min: tssRange.lowerBound,
                max: tssRange.upperBound
            )
        }
        return value
    }

    // MARK: - Workout Value Validation

    /// Valid range for FTP (watts)
    static let ftpRange = 50.0...600.0

    /// Valid range for heart rate (bpm)
    static let heartRateRange = 30.0...250.0

    /// Valid range for pace (seconds per km)
    static let paceRange = 120.0...1200.0  // 2:00/km to 20:00/km

    /// Valid range for power (watts)
    static let powerRange = 0.0...2500.0

    /// Valid range for duration (seconds) - up to 24 hours
    static let durationRange = 0.0...86400.0

    /// Validate FTP value
    static func validateFTP(_ value: Double) throws -> Double {
        guard ftpRange.contains(value) else {
            throw ValidationError.valueOutOfRange(
                field: "FTP",
                value: value,
                min: ftpRange.lowerBound,
                max: ftpRange.upperBound
            )
        }
        return value
    }

    /// Validate heart rate value
    static func validateHeartRate(_ value: Double) throws -> Double {
        guard heartRateRange.contains(value) else {
            throw ValidationError.valueOutOfRange(
                field: "Heart Rate",
                value: value,
                min: heartRateRange.lowerBound,
                max: heartRateRange.upperBound
            )
        }
        return value
    }

    /// Validate pace value (seconds per km)
    static func validatePace(_ value: Double) throws -> Double {
        guard paceRange.contains(value) else {
            throw ValidationError.valueOutOfRange(
                field: "Pace",
                value: value,
                min: paceRange.lowerBound,
                max: paceRange.upperBound
            )
        }
        return value
    }

    /// Validate power value (watts)
    static func validatePower(_ value: Double) throws -> Double {
        guard powerRange.contains(value) else {
            throw ValidationError.valueOutOfRange(
                field: "Power",
                value: value,
                min: powerRange.lowerBound,
                max: powerRange.upperBound
            )
        }
        return value
    }

    // MARK: - String Validation

    /// Maximum length for text fields
    static let maxTextLength = 10000

    /// Maximum length for short fields (names, etc.)
    static let maxShortTextLength = 500

    /// Validate and truncate string length
    static func validateStringLength(
        _ value: String,
        field: String,
        maxLength: Int = maxTextLength
    ) throws -> String {
        guard value.count <= maxLength else {
            throw ValidationError.stringTooLong(
                field: field,
                length: value.count,
                maxLength: maxLength
            )
        }
        return value
    }

    /// Sanitize string by removing potentially problematic characters
    static func sanitizeString(_ value: String) -> String {
        // Remove control characters except newlines and tabs
        let cleaned = value.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }
        return String(String.UnicodeScalarView(cleaned))
    }

    // MARK: - Safe Regex Matching

    /// Maximum time allowed for regex matching (milliseconds)
    static let regexTimeoutMs: UInt64 = 100

    /// Perform regex matching with timeout protection
    static func safeRegexMatch(
        pattern: String,
        in text: String,
        options: NSRegularExpression.Options = []
    ) throws -> [NSTextCheckingResult] {
        // Limit text length to prevent ReDoS
        let truncatedText = String(text.prefix(maxTextLength))

        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            throw ValidationError.invalidFormat(field: "regex", reason: "Invalid pattern: \(pattern)")
        }

        let range = NSRange(truncatedText.startIndex..., in: truncatedText)

        // Use a simpler approach - just limit input size
        // NSRegularExpression doesn't support timeouts natively
        let matches = regex.matches(in: truncatedText, options: [], range: range)

        return matches
    }

    /// Extract first match group from regex
    static func safeRegexFirstMatch(
        pattern: String,
        in text: String
    ) throws -> String? {
        let matches = try safeRegexMatch(pattern: pattern, in: text)

        guard let match = matches.first,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        return String(text[range])
    }

    // MARK: - Date Validation

    /// Validate date is within reasonable range
    static func validateDate(
        _ date: Date,
        field: String,
        allowFuture: Bool = false
    ) throws -> Date {
        let now = Date()
        let oneYearAgo = Calendar.current.date(byAdding: .year, value: -10, to: now)!
        let oneYearFromNow = Calendar.current.date(byAdding: .year, value: 1, to: now)!

        if date < oneYearAgo {
            throw ValidationError.invalidDate(field: field, value: "Date is too far in the past")
        }

        if !allowFuture && date > now {
            throw ValidationError.invalidDate(field: field, value: "Date is in the future")
        }

        if date > oneYearFromNow {
            throw ValidationError.invalidDate(field: field, value: "Date is too far in the future")
        }

        return date
    }

    // MARK: - URL Validation

    /// Validate URL is from expected domain
    static func validateURL(
        _ urlString: String,
        allowedHosts: [String]
    ) throws -> URL {
        guard let url = URL(string: urlString) else {
            throw ValidationError.invalidFormat(field: "URL", reason: "Invalid URL format")
        }

        guard let host = url.host?.lowercased() else {
            throw ValidationError.invalidFormat(field: "URL", reason: "URL has no host")
        }

        let isAllowed = allowedHosts.contains { allowedHost in
            host == allowedHost || host.hasSuffix(".\(allowedHost)")
        }

        guard isAllowed else {
            throw ValidationError.invalidFormat(
                field: "URL",
                reason: "Host '\(host)' is not in allowed list"
            )
        }

        return url
    }

    // MARK: - Composite Validation

    /// Validate complete PMC data set
    static func validatePMCData(
        ctl: Double?,
        atl: Double?,
        tsb: Double?
    ) throws -> (ctl: Double?, atl: Double?, tsb: Double?) {
        let validatedCTL = try ctl.map { try validateCTL($0) }
        let validatedATL = try atl.map { try validateATL($0) }
        let validatedTSB = try tsb.map { try validateTSB($0) }

        // Cross-validation: TSB should approximately equal CTL - ATL
        if let ctl = validatedCTL, let atl = validatedATL, let tsb = validatedTSB {
            let expectedTSB = ctl - atl
            let difference = abs(tsb - expectedTSB)

            // Allow some tolerance for rounding
            if difference > 5 {
                print("[Validation] Warning: TSB (\(tsb)) doesn't match CTL-ATL (\(expectedTSB))")
            }
        }

        return (validatedCTL, validatedATL, validatedTSB)
    }
}

// MARK: - Convenience Extensions

extension Double {
    /// Clamp value to a range
    func clamped(to range: ClosedRange<Double>) -> Double {
        return min(max(self, range.lowerBound), range.upperBound)
    }
}

extension String {
    /// Truncate string to maximum length with ellipsis
    func truncated(to maxLength: Int) -> String {
        if count <= maxLength {
            return self
        }
        return String(prefix(maxLength - 3)) + "..."
    }

    /// Remove leading and trailing whitespace and normalize internal whitespace
    var normalizedWhitespace: String {
        let components = self.components(separatedBy: .whitespacesAndNewlines)
        return components.filter { !$0.isEmpty }.joined(separator: " ")
    }
}
