//
//  ErrorPresenter.swift
//  FitnessApp
//
//  Unified error presentation and recovery handling.
//  Provides consistent error UX across the app.
//

import SwiftUI

// MARK: - App Errors

/// Categorized errors with user-friendly messages and recovery options
enum AppError: LocalizedError, Identifiable {
    case networkError(underlying: Error)
    case healthKitError(underlying: Error)
    case healthKitNotAuthorized
    case storageError(underlying: Error)
    case apiKeyMissing
    case apiKeyInvalid
    case rateLimitExceeded
    case timeout
    case importFailed(reason: String)
    case validationFailed(field: String, reason: String)
    case unknown(underlying: Error)

    var id: String {
        switch self {
        case .networkError: return "network"
        case .healthKitError: return "healthkit"
        case .healthKitNotAuthorized: return "healthkit_auth"
        case .storageError: return "storage"
        case .apiKeyMissing: return "api_key_missing"
        case .apiKeyInvalid: return "api_key_invalid"
        case .rateLimitExceeded: return "rate_limit"
        case .timeout: return "timeout"
        case .importFailed: return "import"
        case .validationFailed: return "validation"
        case .unknown: return "unknown"
        }
    }

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network Connection Error"
        case .healthKitError:
            return "Health Data Error"
        case .healthKitNotAuthorized:
            return "Health Access Required"
        case .storageError:
            return "Storage Error"
        case .apiKeyMissing:
            return "API Key Required"
        case .apiKeyInvalid:
            return "Invalid API Key"
        case .rateLimitExceeded:
            return "Too Many Requests"
        case .timeout:
            return "Request Timed Out"
        case .importFailed(let reason):
            return "Import Failed: \(reason)"
        case .validationFailed(let field, _):
            return "Invalid \(field)"
        case .unknown:
            return "Something Went Wrong"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkError:
            return "Check your internet connection and try again."
        case .healthKitError:
            return "There was a problem reading your health data. Try again or check Health app permissions."
        case .healthKitNotAuthorized:
            return "This app needs access to your health data. Open Settings > Privacy > Health to grant access."
        case .storageError:
            return "There was a problem saving your data. Try restarting the app."
        case .apiKeyMissing:
            return "Add your OpenRouter API key in Settings to enable AI coaching."
        case .apiKeyInvalid:
            return "Your API key appears to be invalid. Check the key in Settings."
        case .rateLimitExceeded:
            return "You've made too many requests. Wait a moment and try again."
        case .timeout:
            return "The request took too long. Check your connection and try again."
        case .importFailed:
            return "The import could not be completed. Check the data format and try again."
        case .validationFailed(_, let reason):
            return reason
        case .unknown:
            return "An unexpected error occurred. Try again or restart the app."
        }
    }

    /// Whether this error supports retry
    var canRetry: Bool {
        switch self {
        case .networkError, .timeout, .rateLimitExceeded, .healthKitError:
            return true
        case .apiKeyMissing, .apiKeyInvalid, .healthKitNotAuthorized:
            return false
        case .storageError, .importFailed, .validationFailed, .unknown:
            return true
        }
    }

    /// Whether this error has a settings action
    var hasSettingsAction: Bool {
        switch self {
        case .apiKeyMissing, .apiKeyInvalid, .healthKitNotAuthorized:
            return true
        default:
            return false
        }
    }

    /// Icon for the error
    var icon: String {
        switch self {
        case .networkError:
            return "wifi.exclamationmark"
        case .healthKitError, .healthKitNotAuthorized:
            return "heart.slash"
        case .storageError:
            return "externaldrive.badge.exclamationmark"
        case .apiKeyMissing, .apiKeyInvalid:
            return "key.slash"
        case .rateLimitExceeded:
            return "hourglass"
        case .timeout:
            return "clock.badge.exclamationmark"
        case .importFailed:
            return "arrow.down.circle.dotted"
        case .validationFailed:
            return "exclamationmark.triangle"
        case .unknown:
            return "questionmark.circle"
        }
    }

    /// Color for the error
    var color: Color {
        switch self {
        case .rateLimitExceeded, .timeout:
            return .orange
        case .apiKeyMissing, .healthKitNotAuthorized:
            return .yellow
        default:
            return .red
        }
    }
}

// MARK: - Error Alert Modifier

/// A view modifier that presents errors in a consistent way
struct ErrorAlertModifier: ViewModifier {
    @Binding var error: AppError?
    var onRetry: (() -> Void)?
    var onSettings: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .alert(
                error?.errorDescription ?? "Error",
                isPresented: Binding(
                    get: { error != nil },
                    set: { if !$0 { error = nil } }
                )
            ) {
                if let error = error {
                    if error.canRetry, let retry = onRetry {
                        Button("Retry") {
                            self.error = nil
                            retry()
                        }
                    }

                    if error.hasSettingsAction, let settings = onSettings {
                        Button("Open Settings") {
                            self.error = nil
                            settings()
                        }
                    }

                    Button("OK", role: .cancel) {
                        self.error = nil
                    }
                }
            } message: {
                if let recovery = error?.recoverySuggestion {
                    Text(recovery)
                }
            }
    }
}

extension View {
    /// Present errors with consistent styling and recovery options
    func errorAlert(
        _ error: Binding<AppError?>,
        onRetry: (() -> Void)? = nil,
        onSettings: (() -> Void)? = nil
    ) -> some View {
        modifier(ErrorAlertModifier(error: error, onRetry: onRetry, onSettings: onSettings))
    }
}

// MARK: - Inline Error Banner

/// A banner for showing errors inline within views
struct ErrorBanner: View {
    let error: AppError
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: error.icon)
                .foregroundStyle(error.color)
                .font(.title3)

            VStack(alignment: .leading, spacing: Spacing.xxxs) {
                Text(error.errorDescription ?? "Error")
                    .font(AppFont.labelMedium)
                    .foregroundStyle(Color.textPrimary)

                if let recovery = error.recoverySuggestion {
                    Text(recovery)
                        .font(AppFont.captionLarge)
                        .foregroundStyle(Color.textSecondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if error.canRetry, let retry = onRetry {
                Button("Retry") {
                    retry()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            if let dismiss = onDismiss {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(Color.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Spacing.sm)
        .background(error.color.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .stroke(error.color.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(error.errorDescription ?? "Error"). \(error.recoverySuggestion ?? "")")
    }
}

// MARK: - Empty State with Error

/// View for showing an empty state that resulted from an error
struct ErrorEmptyState: View {
    let error: AppError
    var onRetry: (() -> Void)?
    var onSettings: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: error.icon)
                .font(.system(size: 48))
                .foregroundStyle(error.color)

            VStack(spacing: Spacing.xs) {
                Text(error.errorDescription ?? "Error")
                    .font(AppFont.titleMedium)
                    .foregroundStyle(Color.textPrimary)

                if let recovery = error.recoverySuggestion {
                    Text(recovery)
                        .font(AppFont.bodyMedium)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            HStack(spacing: Spacing.md) {
                if error.canRetry, let retry = onRetry {
                    Button("Try Again") {
                        retry()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if error.hasSettingsAction, let settings = onSettings {
                    Button("Open Settings") {
                        settings()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(Spacing.xl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(error.errorDescription ?? "Error"). \(error.recoverySuggestion ?? "")")
    }
}

// MARK: - Error Conversion Helpers

extension Error {
    /// Convert any error to an AppError for consistent presentation
    func toAppError() -> AppError {
        // Already an AppError
        if let appError = self as? AppError {
            return appError
        }

        // URLSession errors
        if let urlError = self as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkError(underlying: self)
            case .timedOut:
                return .timeout
            default:
                return .networkError(underlying: self)
            }
        }

        // Generic network-looking errors
        let description = localizedDescription.lowercased()
        if description.contains("network") || description.contains("connection") || description.contains("internet") {
            return .networkError(underlying: self)
        }
        if description.contains("timeout") || description.contains("timed out") {
            return .timeout
        }
        if description.contains("health") || description.contains("healthkit") {
            return .healthKitError(underlying: self)
        }

        return .unknown(underlying: self)
    }
}

// MARK: - Preview

#Preview("Error Banner") {
    VStack(spacing: Spacing.md) {
        ErrorBanner(
            error: .networkError(underlying: URLError(.notConnectedToInternet)),
            onRetry: { },
            onDismiss: { }
        )

        ErrorBanner(
            error: .apiKeyMissing,
            onDismiss: { }
        )

        ErrorBanner(
            error: .timeout,
            onRetry: { },
            onDismiss: { }
        )
    }
    .padding()
    .background(Color.backgroundPrimary)
}

#Preview("Error Empty State") {
    ErrorEmptyState(
        error: .healthKitNotAuthorized,
        onRetry: { },
        onSettings: { }
    )
    .background(Color.backgroundPrimary)
}
