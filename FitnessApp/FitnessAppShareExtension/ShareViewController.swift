import UIKit
import Social
import UniformTypeIdentifiers

/// Share Extension for receiving TrainingPeaks workouts via URL, text, or screenshots
class ShareViewController: UIViewController {

    private let appGroupIdentifier = "group.com.bobk.FitnessApp"
    private let sharedImageKey = "sharedScreenshot"
    private let sharedWorkoutKey = "sharedWorkout"
    private let calibrateURLScheme = "fitnesscoach://calibrate"
    private let importWorkoutURLScheme = "fitnesscoach://import-workout"

    /// Content type being shared
    private enum SharedContentType {
        case url
        case text
        case image
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Use transparent background - we'll process quickly and open the app
        view.backgroundColor = .clear
        handleSharedContent()
    }

    private func handleSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            completeRequest(success: false, contentType: nil)
            return
        }

        // Priority: URL > Text > Image
        // This order makes sense because TrainingPeaks shares as URL typically

        // Look for URL attachments first (most reliable)
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                loadURL(from: attachment)
                return
            }
        }

        // Then try plain text (for copy-pasted share text)
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                loadText(from: attachment)
                return
            }
        }

        // Finally try images (screenshot calibration - legacy flow)
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                loadImage(from: attachment)
                return
            }
        }

        // Nothing found
        completeRequest(success: false, contentType: nil)
    }

    // MARK: - URL Handling

    private func loadURL(from attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, error in
            guard let self = self else { return }

            if let error = error {
                print("[ShareExtension] Error loading URL: \(error)")
                self.completeRequest(success: false, contentType: .url)
                return
            }

            guard let url = item as? URL else {
                print("[ShareExtension] Could not cast item to URL")
                self.completeRequest(success: false, contentType: .url)
                return
            }

            // Check if this looks like a TrainingPeaks URL
            let urlString = url.absoluteString
            if self.isTrainingPeaksURL(urlString) {
                print("[ShareExtension] TrainingPeaks URL detected: \(urlString)")
                self.saveWorkoutToAppGroup(urlString: urlString, text: nil)
                self.completeRequest(success: true, contentType: .url)
            } else {
                print("[ShareExtension] Non-TP URL received: \(urlString)")
                // Still save it - might be useful
                self.saveWorkoutToAppGroup(urlString: urlString, text: nil)
                self.completeRequest(success: true, contentType: .url)
            }
        }
    }

    // MARK: - Text Handling

    private func loadText(from attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, error in
            guard let self = self else { return }

            if let error = error {
                print("[ShareExtension] Error loading text: \(error)")
                self.completeRequest(success: false, contentType: .text)
                return
            }

            guard let text = item as? String else {
                print("[ShareExtension] Could not cast item to String")
                self.completeRequest(success: false, contentType: .text)
                return
            }

            print("[ShareExtension] Text content received: \(text.prefix(100))...")

            // Check if text contains a TrainingPeaks URL or workout info
            if let tpURL = self.extractTrainingPeaksURL(from: text) {
                print("[ShareExtension] Extracted TP URL from text: \(tpURL)")
                self.saveWorkoutToAppGroup(urlString: tpURL, text: text)
                self.completeRequest(success: true, contentType: .text)
            } else if self.containsWorkoutInfo(text) {
                // Text might contain workout details even without URL
                print("[ShareExtension] Text appears to contain workout info")
                self.saveWorkoutToAppGroup(urlString: nil, text: text)
                self.completeRequest(success: true, contentType: .text)
            } else {
                print("[ShareExtension] Text doesn't appear to be workout-related")
                self.completeRequest(success: false, contentType: .text)
            }
        }
    }

    // MARK: - Workout Content Helpers

    /// Check if a URL appears to be from TrainingPeaks
    private func isTrainingPeaksURL(_ urlString: String) -> Bool {
        let lowercased = urlString.lowercased()
        return lowercased.contains("trainingpeaks.com") ||
               lowercased.contains("tpks.ws")
    }

    /// Extract a TrainingPeaks URL from text
    private func extractTrainingPeaksURL(from text: String) -> String? {
        // Match TrainingPeaks URLs (both full and short formats)
        let patterns = [
            "https?://[\\w.]*trainingpeaks\\.com/[\\w/?=&-]+",
            "https?://tpks\\.ws/[\\w/?=&-]+"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(text.startIndex..., in: text)
                if let match = regex.firstMatch(in: text, options: [], range: range) {
                    if let matchRange = Range(match.range, in: text) {
                        return String(text[matchRange])
                    }
                }
            }
        }
        return nil
    }

    /// Check if text contains workout-related information
    private func containsWorkoutInfo(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        // Look for common TP share text patterns
        return lowercased.contains("tss") ||
               lowercased.contains("stss") ||
               lowercased.contains("workout") ||
               lowercased.contains("training")
    }

    /// Save workout content to App Group for main app to read
    private func saveWorkoutToAppGroup(urlString: String?, text: String?) {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print("[ShareExtension] ERROR: Could not access UserDefaults for app group")
            return
        }

        // Create a dictionary with the shared content
        var workoutData: [String: Any] = [
            "timestamp": Date().timeIntervalSince1970
        ]

        if let url = urlString {
            workoutData["url"] = url
        }

        if let text = text {
            workoutData["text"] = text
        }

        userDefaults.set(workoutData, forKey: sharedWorkoutKey)
        userDefaults.set(Date(), forKey: "sharedWorkoutDate")
        userDefaults.synchronize()

        print("[ShareExtension] Saved workout data to app group")
    }

    // MARK: - Image Handling (Legacy Screenshot Flow)

    private func loadImage(from attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
            guard let self = self else { return }

            if let error = error {
                print("[ShareExtension] Error loading image: \(error)")
                self.completeRequest(success: false, contentType: .image)
                return
            }

            var imageData: Data?

            if let url = item as? URL {
                imageData = try? Data(contentsOf: url)
            } else if let data = item as? Data {
                imageData = data
            } else if let image = item as? UIImage {
                imageData = image.pngData()
            }

            guard let data = imageData else {
                self.completeRequest(success: false, contentType: .image)
                return
            }

            // Save to app group container
            self.saveImageToAppGroup(data)
            self.completeRequest(success: true, contentType: .image)
        }
    }

    private func saveImageToAppGroup(_ imageData: Data) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            print("[ShareExtension] ERROR: Could not access app group container for: \(appGroupIdentifier)")
            return
        }

        print("[ShareExtension] App group container: \(containerURL.path)")

        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "screenshot_\(timestamp).png"
        let fileURL = containerURL.appendingPathComponent(filename)

        do {
            try imageData.write(to: fileURL)
            print("[ShareExtension] File written successfully to: \(fileURL.path)")
            print("[ShareExtension] File size: \(imageData.count) bytes")

            // Store the filename in UserDefaults for the main app to find
            guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
                print("[ShareExtension] ERROR: Could not access UserDefaults for app group")
                return
            }

            userDefaults.set(filename, forKey: sharedImageKey)
            userDefaults.set(Date(), forKey: "sharedScreenshotDate")
            userDefaults.synchronize()

            print("[ShareExtension] UserDefaults updated with filename: \(filename)")

            // Verify the write
            if FileManager.default.fileExists(atPath: fileURL.path) {
                print("[ShareExtension] Verified: File exists at path")
            } else {
                print("[ShareExtension] WARNING: File verification failed!")
            }
        } catch {
            print("[ShareExtension] ERROR saving screenshot: \(error)")
        }
    }

    private func completeRequest(success: Bool, contentType: SharedContentType?) {
        DispatchQueue.main.async {
            if success {
                // Open the main app with appropriate URL scheme
                self.openMainApp(contentType: contentType ?? .image)
            } else {
                self.extensionContext?.cancelRequest(withError: ShareError.invalidContent)
            }
        }
    }

    /// Open the main app using URL scheme
    private func openMainApp(contentType: SharedContentType) {
        // Choose URL scheme based on content type
        let urlScheme: String
        switch contentType {
        case .url, .text:
            urlScheme = importWorkoutURLScheme
        case .image:
            urlScheme = calibrateURLScheme
        }

        guard let url = URL(string: urlScheme) else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        print("[ShareExtension] Opening main app with URL: \(urlScheme)")

        // Use the responder chain to open URLs from extension
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                application.open(url, options: [:], completionHandler: nil)
                break
            }
            responder = responder?.next
        }

        // Also try the extensionContext method (iOS 15+)
        extensionContext?.open(url) { success in
            print("[ShareExtension] Open URL result: \(success)")
        }

        // Complete the extension request
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}

// MARK: - Errors

enum ShareError: Error {
    case invalidContent
    case saveFailed
}
