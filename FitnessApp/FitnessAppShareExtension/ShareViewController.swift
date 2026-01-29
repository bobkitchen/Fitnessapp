import UIKit
import Social
import UniformTypeIdentifiers

/// Share Extension for receiving screenshots for PMC calibration
class ShareViewController: UIViewController {

    private let appGroupIdentifier = "group.com.bobk.FitnessApp"
    private let sharedImageKey = "sharedScreenshot"
    private let calibrateURLScheme = "fitnesscoach://calibrate"

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        handleSharedContent()
    }

    private func handleSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            completeRequest(success: false)
            return
        }

        // Look for image attachments (screenshot calibration)
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                loadImage(from: attachment)
                return
            }
        }

        // Nothing supported found
        completeRequest(success: false)
    }

    // MARK: - Image Handling

    private func loadImage(from attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, error in
            guard let self = self else { return }

            if let error = error {
                print("[ShareExtension] Error loading image: \(error)")
                self.completeRequest(success: false)
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
                self.completeRequest(success: false)
                return
            }

            self.saveImageToAppGroup(data)
            self.completeRequest(success: true)
        }
    }

    private func saveImageToAppGroup(_ imageData: Data) {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            print("[ShareExtension] ERROR: Could not access app group container")
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let filename = "screenshot_\(timestamp).png"
        let fileURL = containerURL.appendingPathComponent(filename)

        do {
            try imageData.write(to: fileURL)

            guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
                print("[ShareExtension] ERROR: Could not access UserDefaults for app group")
                return
            }

            userDefaults.set(filename, forKey: sharedImageKey)
            userDefaults.set(Date(), forKey: "sharedScreenshotDate")
            userDefaults.synchronize()

            print("[ShareExtension] Saved screenshot: \(filename)")
        } catch {
            print("[ShareExtension] ERROR saving screenshot: \(error)")
        }
    }

    private func completeRequest(success: Bool) {
        DispatchQueue.main.async {
            if success {
                self.openMainApp()
            } else {
                self.extensionContext?.cancelRequest(withError: ShareError.invalidContent)
            }
        }
    }

    private func openMainApp() {
        guard let url = URL(string: calibrateURLScheme) else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        extensionContext?.open(url) { success in
            print("[ShareExtension] Open URL result: \(success)")
        }

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
