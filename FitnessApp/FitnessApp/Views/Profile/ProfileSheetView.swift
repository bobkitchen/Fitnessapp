import SwiftUI
import SwiftData

/// Full-screen profile sheet styled like The Outsiders app
struct ProfileSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [AthleteProfile]

    @State private var showingAPIKeySheet = false
    @State private var showingTPImportSheet = false
    @State private var showingAboutSheet = false
    @State private var showingPhotoOptions = false
    @State private var showingImagePicker = false
    @State private var showingCamera = false
    @State private var accountBalance: String?
    @State private var isLoadingBalance = false

    private var profile: AthleteProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Spacing.lg) {
                    // Hero avatar section
                    avatarSection

                    // Settings sections
                    settingsSections
                }
                .padding(Layout.screenPadding)
            }
            .background(Color.backgroundPrimary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.backgroundPrimary, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.textTertiary)
                    }
                }
            }
            .sheet(isPresented: $showingAPIKeySheet) {
                APIKeySettingsView()
            }
            .sheet(isPresented: $showingTPImportSheet) {
                TPWorkoutImportView()
            }
            .sheet(isPresented: $showingAboutSheet) {
                AboutView()
            }
            .confirmationDialog("Change Photo", isPresented: $showingPhotoOptions) {
                Button("Choose from Library") {
                    showingImagePicker = true
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("Take Photo") {
                        showingCamera = true
                    }
                }
                if profile?.profilePhotoData != nil {
                    Button("Remove Photo", role: .destructive) {
                        removePhoto()
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $showingImagePicker) {
                PhotoLibraryPicker(isPresented: $showingImagePicker) { image in
                    savePhoto(image)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView(isPresented: $showingCamera) { image in
                    savePhoto(image)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Avatar Section

    @ViewBuilder
    private var avatarSection: some View {
        VStack(spacing: Spacing.md) {
            // Large circular avatar (120pt like The Outsiders)
            Button {
                showingPhotoOptions = true
            } label: {
                ZStack {
                    if let photoData = profile?.profilePhotoData,
                       let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 120, height: 120)
                            .clipShape(Circle())
                    } else if let initials = profile?.initials, !initials.isEmpty {
                        ZStack {
                            Circle()
                                .fill(Color.backgroundTertiary)
                            Text(initials)
                                .font(.system(size: 44, weight: .semibold, design: .rounded))
                                .foregroundStyle(Color.textSecondary)
                        }
                        .frame(width: 120, height: 120)
                    } else {
                        ZStack {
                            Circle()
                                .fill(Color.backgroundTertiary)
                            Image(systemName: "person.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(Color.textTertiary)
                        }
                        .frame(width: 120, height: 120)
                    }

                    // Camera badge
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(8)
                                .background(Color.accentPrimary)
                                .clipShape(Circle())
                                .offset(x: -8, y: -8)
                        }
                    }
                    .frame(width: 120, height: 120)
                }
            }
            .buttonStyle(.plain)

            // Name
            if let profile {
                Text(profile.name.isEmpty ? "Add Your Name" : profile.name)
                    .font(AppFont.titleMedium)
                    .foregroundStyle(Color.textPrimary)

                if let age = profile.age {
                    Text("\(age) years old")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Color.textSecondary)
                }
            }
        }
        .padding(.top, Spacing.lg)
        .padding(.bottom, Spacing.md)
    }

    // MARK: - Settings Sections

    @ViewBuilder
    private var settingsSections: some View {
        VStack(spacing: Spacing.lg) {
            // PERSONALIZE Section
            SettingsSection(title: "PERSONALIZE") {
                if let profile {
                    NavigationLink {
                        ProfileEditView(profile: profile)
                    } label: {
                        SettingsRow(icon: "person.fill", iconColor: .accentSecondary, title: "Personal & Fitness Details")
                    }

                    NavigationLink {
                        ThresholdEditView(profile: profile)
                    } label: {
                        SettingsRow(icon: "speedometer", iconColor: .accentPrimary, title: "Training Thresholds")
                    }
                } else {
                    Button {
                        createProfile()
                    } label: {
                        SettingsRow(icon: "person.badge.plus", iconColor: .accentSecondary, title: "Create Profile")
                    }
                }
            }

            // AI COACH Section
            SettingsSection(title: "AI COACH") {
                Button {
                    showingAPIKeySheet = true
                } label: {
                    HStack {
                        SettingsRow(icon: "key.fill", iconColor: .statusModerate, title: "API Settings")
                        Spacer()
                        if hasAPIKey {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                NavigationLink {
                    ModelSelectionView()
                } label: {
                    SettingsRow(icon: "cpu", iconColor: .chartFitness, title: "Model Selection")
                }

                NavigationLink {
                    MemoriesManagementView()
                } label: {
                    SettingsRow(icon: "brain", iconColor: .chartFatigue, title: "Memory")
                }

                NavigationLink {
                    CoachingPreferencesView()
                } label: {
                    SettingsRow(icon: "slider.horizontal.3", iconColor: .accentSecondary, title: "Preferences")
                }
            }

            // DATA Section
            SettingsSection(title: "DATA") {
                NavigationLink {
                    HealthKitSettingsView()
                } label: {
                    SettingsRow(icon: "heart.fill", iconColor: Color(red: 1, green: 0.2, blue: 0.3), title: "Apple Health")
                }

                Button {
                    showingTPImportSheet = true
                } label: {
                    HStack {
                        SettingsRow(icon: "link.badge.plus", iconColor: .accentPrimary, title: "TrainingPeaks Import")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                NavigationLink {
                    DataManagementView()
                } label: {
                    SettingsRow(icon: "externaldrive", iconColor: .textSecondary, title: "Data Management")
                }
            }

            // ABOUT Section
            SettingsSection(title: "ABOUT") {
                Button {
                    showingAboutSheet = true
                } label: {
                    HStack {
                        SettingsRow(icon: "info.circle", iconColor: .accentSecondary, title: "App Info")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                Link(destination: URL(string: "https://github.com")!) {
                    HStack {
                        SettingsRow(icon: "hand.raised", iconColor: .statusOptimal, title: "Privacy Policy")
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(Color.textTertiary)
                    }
                }

                HStack {
                    SettingsRow(icon: "number", iconColor: .textTertiary, title: "Version")
                    Spacer()
                    Text("1.0.0")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Color.textTertiary)
                }
            }
        }
    }

    // MARK: - Helper Views & Methods

    private var hasAPIKey: Bool {
        UserDefaults.standard.bool(forKey: "hasOpenRouterAPIKey")
    }

    private func createProfile() {
        let newProfile = AthleteProfile()
        modelContext.insert(newProfile)
    }

    private func savePhoto(_ image: UIImage) {
        // Image is already cropped by iOS native crop UI
        // Resize to 500x500 for storage efficiency
        let resized = resizeImage(image, targetSize: CGSize(width: 500, height: 500))
        if let jpegData = resized.jpegData(compressionQuality: 0.8) {
            profile?.profilePhotoData = jpegData
            try? modelContext.save()
        }
    }

    private func removePhoto() {
        profile?.profilePhotoData = nil
        try? modelContext.save()
    }

    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        let widthRatio = targetSize.width / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = min(widthRatio, heightRatio)

        let newSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let rect = CGRect(origin: .zero, size: newSize)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage ?? image
    }
}

// MARK: - Settings Section Container

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title)
                .font(AppFont.labelSmall)
                .foregroundStyle(Color.textTertiary)
                .tracking(0.5)

            VStack(spacing: 0) {
                content()
            }
            .padding(Spacing.md)
            .background(Color.backgroundSecondary)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.large))
        }
    }
}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String

    var body: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: IconSize.medium))
                .foregroundStyle(iconColor)
                .frame(width: 28)

            Text(title)
                .font(AppFont.bodyMedium)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.vertical, Spacing.xs)
    }
}

// MARK: - Photo Library Picker

/// UIViewControllerRepresentable for photo library with native iOS crop UI
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImageSelected: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.allowsEditing = true  // Enables native "Move and Scale" crop UI
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoLibraryPicker

        init(_ parent: PhotoLibraryPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Use editedImage (cropped by iOS) if available, fallback to original
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                parent.onImageSelected(image)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Camera View

/// UIViewControllerRepresentable for camera with native iOS crop UI
struct CameraView: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.allowsEditing = true  // Enables native "Move and Scale" crop UI
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraView

        init(_ parent: CameraView) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Use editedImage (cropped by iOS) if available, fallback to original
            if let image = info[.editedImage] as? UIImage ?? info[.originalImage] as? UIImage {
                parent.onImageCaptured(image)
            }
            parent.isPresented = false
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.isPresented = false
        }
    }
}

// MARK: - Preview

#Preview {
    ProfileSheetView()
        .modelContainer(for: [AthleteProfile.self, UserMemory.self], inMemory: true)
}
