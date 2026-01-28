import SwiftUI
import SwiftData

/// Circular avatar button for navigation bar that opens the profile sheet
struct ProfileAvatarButton: View {
    @Binding var showingProfile: Bool
    @Query private var profiles: [AthleteProfile]
    @Environment(ReadinessStateService.self) private var readinessState: ReadinessStateService?

    private var profile: AthleteProfile? { profiles.first }

    /// Avatar size (default 34pt for toolbar, matching The Outsiders pattern)
    var size: CGFloat = 34

    /// Border color based on readiness grade
    private var borderColor: Color {
        readinessState?.gradeColor ?? Color.accentPrimary.opacity(0.5)
    }

    var body: some View {
        Button {
            showingProfile = true
        } label: {
            avatarContent
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let photoData = profile?.profilePhotoData,
           let uiImage = UIImage(data: photoData) {
            // User photo
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(borderColor, lineWidth: 3)
                )
        } else if let initials = profile?.initials, !initials.isEmpty {
            // Initials placeholder
            ZStack {
                Circle()
                    .fill(Color.backgroundTertiary)

                Text(initials)
                    .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.textSecondary)
            }
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(borderColor, lineWidth: 3)
            )
        } else {
            // Default person icon
            ZStack {
                Circle()
                    .fill(Color.backgroundTertiary)

                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.45))
                    .foregroundStyle(Color.textTertiary)
            }
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(borderColor, lineWidth: 3)
            )
        }
    }
}

// MARK: - Preview

#Preview {
    HStack(spacing: 20) {
        ProfileAvatarButton(showingProfile: .constant(false))
        ProfileAvatarButton(showingProfile: .constant(false), size: 44)
        ProfileAvatarButton(showingProfile: .constant(false), size: 80)
    }
    .padding()
    .background(Color.backgroundPrimary)
    .modelContainer(for: AthleteProfile.self, inMemory: true)
    .environment(ReadinessStateService())
}
