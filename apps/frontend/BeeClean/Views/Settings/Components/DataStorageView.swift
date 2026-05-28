import SwiftUI

// MARK: - Data & Storage View
struct DataStorageView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var urlCacheSize: String = "..."
    @State private var tmpSize: String = "..."
    @State private var documentsSize: String = "..."
    @State private var totalSize: String = "..."
    @State private var appeared = false
    @State private var cleared = false

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            AmbientGlowView()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Button {
                        HapticManager.shared.arrowNudge(.backward)
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
                                    )
                            )
                    }

                    Text("Data & Storage")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.leading, 8)

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 14) {
                        // Storage rows
                        StorageRow(
                            icon: "globe",
                            title: "URL Cache",
                            subtitle: "Cached network responses",
                            color: Color(hex: "60A5FA"),
                            size: urlCacheSize
                        )
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.0), value: appeared)

                        StorageRow(
                            icon: "doc.fill",
                            title: "Temporary Files",
                            subtitle: "Temp data & thumbnails",
                            color: Color(hex: "FB923C"),
                            size: tmpSize
                        )
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.07), value: appeared)

                        StorageRow(
                            icon: "folder.fill",
                            title: "App Documents",
                            subtitle: "Saved preferences & data",
                            color: Color(hex: "A78BFA"),
                            size: documentsSize
                        )
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.14), value: appeared)

                        // Total card
                        HStack {
                            HStack(spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.primaryColor.opacity(0.15), Color.primaryColor.opacity(0.06)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(Color.primaryColor.opacity(0.15), lineWidth: 0.5)
                                        )
                                        .frame(width: 40, height: 40)

                                    Image(systemName: "externaldrive.fill")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.primaryColor)
                                }
                                .shadow(color: Color.primaryColor.opacity(0.15), radius: 6)

                                Text("Total App Storage")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            Spacer()

                            Text(totalSize)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [Color.primaryColor, Color(hex: "00B4D8")],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.surfaceMedium)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(
                                            LinearGradient(
                                                colors: [Color.primaryColor.opacity(0.04), Color.clear],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(
                                    LinearGradient(
                                        colors: [Color.primaryColor.opacity(0.15), Color.primaryColor.opacity(0.05)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .shadow(color: Color.primaryColor.opacity(0.06), radius: 12, y: 4)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.21), value: appeared)

                        // Clear cache button
                        Button {
                            clearAllCaches()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: cleared ? "checkmark.circle.fill" : "trash.fill")
                                    .font(.system(size: 15))
                                Text(cleared ? "Cache Cleared" : "Clear All Cache")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        cleared
                                            ? LinearGradient(
                                                colors: [Color.primaryColor, Color(hex: "00B4D8")],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                            : LinearGradient(
                                                colors: [Color(hex: "EF4444"), Color(hex: "DC2626")],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.12), Color.clear],
                                            startPoint: .top,
                                            endPoint: .center
                                        )
                                    )
                            )
                            .shadow(color: cleared ? Color.primaryColor.opacity(0.25) : Color(hex: "EF4444").opacity(0.25), radius: 12, y: 4)
                        }
                        .padding(.top, 8)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 16)
                        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.28), value: appeared)

                        // Privacy note
                        HStack(spacing: 8) {
                            Image(systemName: "lock.shield.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.primaryColor.opacity(0.5))
                            Text("All data is stored locally on your device.\nNothing is uploaded to external servers.")
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.30))
                                .lineSpacing(2)
                        }
                        .padding(.top, 12)
                        .opacity(appeared ? 1 : 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 100)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            calculateSizes()
            withAnimation { appeared = true }
        }
    }

    private func calculateSizes() {
        // Walk tmp + Documents off-main. The previous on-main version
        // stalled the Settings push for 10–500ms on devices with
        // cluttered tmp dirs (every PHImageManager preview, every cached
        // thumbnail, every scan-result JSON sits under tmp), and the
        // walk runs again on every clear-cache tap. Hop to a userInitiated
        // background queue, then dispatch the formatted strings back to
        // main when ready — the pill labels show "..." in the meantime,
        // which is fine because they're already initialized to "...".
        urlCacheSize = "..."
        tmpSize = "..."
        documentsSize = "..."
        totalSize = "..."

        DispatchQueue.global(qos: .userInitiated).async {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file

            let urlBytes = Int64(URLCache.shared.currentDiskUsage)
            let tmpBytes = Self.directorySize(url: FileManager.default.temporaryDirectory)
            let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            let docsBytes = docsURL.map { Self.directorySize(url: $0) } ?? 0
            let total = urlBytes + tmpBytes + docsBytes

            let urlStr = formatter.string(fromByteCount: urlBytes)
            let tmpStr = formatter.string(fromByteCount: tmpBytes)
            let docsStr = docsURL == nil ? "0 KB" : formatter.string(fromByteCount: docsBytes)
            let totalStr = formatter.string(fromByteCount: total)

            DispatchQueue.main.async {
                urlCacheSize = urlStr
                tmpSize = tmpStr
                documentsSize = docsStr
                totalSize = totalStr
            }
        }
    }

    /// `static` so the background queue doesn't capture `self` (which
    /// would otherwise pin the View struct's @State storage to the
    /// background queue's lifetime). Pure function — no instance state.
    private static func directorySize(url: URL) -> Int64 {
        var total: Int64 = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    private func clearAllCaches() {
        // URLCache.removeAllCachedResponses is fast and safe on main.
        URLCache.shared.removeAllCachedResponses()

        // The tmp-directory wipe used to run inline on main and could
        // stall 100ms+ on devices with hundreds of cached PHImageManager
        // previews + scan-result JSON. Hop to a userInitiated queue and
        // re-trigger size calculation after the wipe completes — the
        // user gets the haptic + UI affordance immediately.
        HapticManager.shared.notify(.success)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
            cleared = true
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let tmp = FileManager.default.temporaryDirectory
            if let files = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) {
                for file in files { try? FileManager.default.removeItem(at: file) }
            }
            DispatchQueue.main.async {
                calculateSizes()
            }
        }

        // Reset after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation { cleared = false }
        }
    }
}

// MARK: - Storage Row
private struct StorageRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let size: String

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.15), color.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(color.opacity(0.15), lineWidth: 0.5)
                    )
                    .frame(width: 44, height: 44)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(color)
            }
            .shadow(color: color.opacity(0.15), radius: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer()

            Text(size)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                )
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.surfaceMedium)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.05), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
    }
}
