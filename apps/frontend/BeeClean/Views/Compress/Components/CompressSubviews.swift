import SwiftUI
import Photos

// MARK: - Bitepal Compress Chrome
//
// Shared backgrounds for the redesigned Photo/Video compress detail bottom
// panel. Centralized so the level chips and primary CTA stay visually in
// sync across both flows — Apple Design Award polish, one source of truth.

/// Background for a level-picker chip. Bitepal pill aesthetic: flat
/// lavender chip when unselected, solid ink capsule when selected.
/// No glass, no sheen, no border — clean and decisive.
struct BitepalChipBackground: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(isSelected ? Color(hex: "0A0A0A") : Color(hex: "EEEDF3"))
    }
}

/// Primary CTA background — solid ink capsule with a soft drop shadow.
/// Matches the Bitepal "Apply Filters" CTA. No gradient, no sheen.
struct BitepalPrimaryButtonBackground: View {
    var body: some View {
        Capsule()
            .fill(Color(hex: "0A0A0A"))
            .shadow(color: Color(hex: "0A0A0A").opacity(0.22), radius: 14, y: 6)
    }
}

// MARK: - Empty Photos View
struct EmptyPhotosView: View {
    @State private var permissionDenied = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.surfaceLight)
                    .frame(width: 72, height: 72)

                Image(systemName: permissionDenied ? "lock.shield" : "photo.on.rectangle")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(permissionDenied ? .orange.opacity(0.7) : .foregroundSecondary.opacity(0.45))
            }

            VStack(spacing: 6) {
                Text(permissionDenied ? "Photo Access Required" : BCLoc.noPhotosFound.tr)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.foreground)

                Text(permissionDenied
                     ? "Grant photo library access in\nSettings to compress your photos."
                     : BCLoc.noPhotosFoundSubtitle.tr)
                    .font(.system(size: 14))
                    .foregroundColor(.mutedForeground)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            if permissionDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(BCLoc.openSettings.tr)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(hex: "3B82F6"))
                        .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 40)
        .task {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            permissionDenied = (status == .denied || status == .restricted)
        }
    }
}

// MARK: - Empty Videos View
struct EmptyVideosView: View {
    @State private var permissionDenied = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.surfaceLight)
                    .frame(width: 72, height: 72)

                Image(systemName: permissionDenied ? "lock.shield" : "video.slash")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(permissionDenied ? .orange.opacity(0.7) : .foregroundSecondary.opacity(0.45))
            }

            VStack(spacing: 6) {
                Text(permissionDenied ? "Photo Access Required" : BCLoc.noVideosFound.tr)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.foreground)

                Text(permissionDenied
                     ? "Grant photo library access in\nSettings to compress your videos."
                     : BCLoc.noVideosFoundSubtitle.tr)
                    .font(.system(size: 14))
                    .foregroundColor(.mutedForeground)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }

            if permissionDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text(BCLoc.openSettings.tr)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color(hex: "3B82F6"))
                        .cornerRadius(10)
                }
            }
        }
        .padding(.horizontal, 40)
        .task {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            permissionDenied = (status == .denied || status == .restricted)
        }
    }
}
