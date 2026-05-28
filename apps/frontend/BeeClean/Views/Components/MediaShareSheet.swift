import SwiftUI
import Photos
import UIKit
import AVFoundation

// MARK: - Media Share Sheet
//
// Custom bottom-sheet share UI for a single PHAsset. First row of tiles
// surfaces the most-requested in-app targets (Messages, Stories,
// Snapchat, Feed, Email). "More" opens the native UIActivityViewController
// for everything else.
//
// Targets that have a documented URL scheme (Snapchat camera, Instagram
// Stories) open via deep-link; everything else routes through the
// system share sheet. Tiles fail-gracefully — if a target app isn't
// installed, we fall back to the system sheet.

struct MediaShareSheet: View {
    let assetId: String
    var onDismiss: () -> Void = {}

    @State private var isLoadingAsset = false
    @State private var preparedAsset: PreparedShareAsset?
    @State private var showActivityView = false

    var body: some View {
        VStack(spacing: 0) {
            // BitePal-style grip — small grey pill at the very top so
            // the sheet reads as a tactile draggable surface.
            Capsule()
                .fill(Color.black.opacity(0.16))
                .frame(width: 38, height: 4)
                .padding(.top, 10)
                .padding(.bottom, 14)

            header
                .padding(.horizontal, 22)
                .padding(.bottom, 22)

            grid
                .padding(.horizontal, 22)
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 24, y: 8)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
        .task { prepareAsset() }
        .sheet(isPresented: $showActivityView) {
            if let item = preparedAsset?.activityItem {
                ActivityViewControllerWrapper(activityItems: [item])
                    .presentationDetents([.medium, .large])
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Share to…")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(Color(hex: "0A0A0A"))
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(hex: "6B7280"))
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color(hex: "F2F2F7")))
            }
            .buttonStyle(.plain)
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 14),
                count: 4
            ),
            spacing: 18
        ) {
            tile(.messages)
            tile(.stories)
            tile(.snapchat)
            tile(.feed)
            tile(.email)
            tile(.more)
        }
    }

    private func tile(_ target: ShareTarget) -> some View {
        Button(action: { handleTap(target) }) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(target.tint)
                        .frame(width: 56, height: 56)
                        .shadow(color: target.tint.opacity(0.35), radius: 8, y: 3)
                    target.iconView
                }
                Text(target.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "0A0A0A"))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoadingAsset && target != .more)
    }

    // MARK: - Asset prep

    private func prepareAsset() {
        guard preparedAsset == nil else { return }
        isLoadingAsset = true
        Task {
            let prepared = await PreparedShareAsset.load(assetId: assetId)
            await MainActor.run {
                preparedAsset = prepared
                isLoadingAsset = false
            }
        }
    }

    // MARK: - Tap routing

    private func handleTap(_ target: ShareTarget) {
        HapticManager.shared.impact(.light)
        switch target {
        case .messages, .email, .feed:
            // Fall through to system share sheet — Messages composer,
            // Mail composer, and Facebook all live there as activity
            // types, no first-party SDK needed.
            showActivityView = true
        case .stories:
            openInstagramStories()
        case .snapchat:
            openSnapchat()
        case .more:
            showActivityView = true
        }
    }

    private func openInstagramStories() {
        guard let item = preparedAsset?.fileURL,
              let scheme = URL(string: "instagram-stories://share") else {
            showActivityView = true
            return
        }
        if UIApplication.shared.canOpenURL(scheme) {
            let pasteboardItems: [String: Any] = [
                preparedAsset?.isVideo == true
                    ? "com.instagram.sharedSticker.backgroundVideo"
                    : "com.instagram.sharedSticker.backgroundImage": (try? Data(contentsOf: item)) ?? Data()
            ]
            UIPasteboard.general.setItems(
                [pasteboardItems],
                options: [.expirationDate: Date().addingTimeInterval(60 * 5)]
            )
            UIApplication.shared.open(scheme)
        } else {
            showActivityView = true
        }
    }

    private func openSnapchat() {
        guard let scheme = URL(string: "snapchat://creativekit/camera/1")
                ?? URL(string: "snapchat://") else {
            showActivityView = true
            return
        }
        if UIApplication.shared.canOpenURL(scheme) {
            UIApplication.shared.open(scheme)
        } else {
            showActivityView = true
        }
    }
}

// MARK: - Share Target

private enum ShareTarget {
    case messages, stories, snapchat, feed, email, more

    var label: String {
        switch self {
        case .messages: return "Messages"
        case .stories:  return "Stories"
        case .snapchat: return "Snapchat"
        case .feed:     return "Feed"
        case .email:    return "Email"
        case .more:     return "More"
        }
    }

    var tint: Color {
        switch self {
        case .messages: return Color(hex: "2ECB55")
        case .stories:  return Color(hex: "E1306C")
        case .snapchat: return Color(hex: "FFFC00")
        case .feed:     return Color(hex: "1877F2")
        case .email:    return Color(hex: "2A82F2")
        case .more:     return Color(hex: "8E8E93")
        }
    }

    @ViewBuilder
    var iconView: some View {
        switch self {
        case .messages:
            Image(systemName: "message.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
        case .stories:
            Image(systemName: "camera.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        case .snapchat:
            Image(systemName: "ghost")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.black)
        case .feed:
            Text("f")
                .font(.system(size: 26, weight: .heavy, design: .serif))
                .foregroundColor(.white)
        case .email:
            Image(systemName: "envelope.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)
        case .more:
            Image(systemName: "ellipsis")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Prepared Share Asset

private struct PreparedShareAsset {
    let fileURL: URL
    let isVideo: Bool

    var activityItem: Any { fileURL }

    static func load(assetId: String) async -> PreparedShareAsset? {
        await withCheckedContinuation { (continuation: CheckedContinuation<PreparedShareAsset?, Never>) in
            // Single-resume guard. PHImageManager's request callbacks
            // can fire MULTIPLE times for the same request (degraded
            // image first, high-quality second, or success + iCloud
            // download progress callbacks). CheckedContinuation crashes
            // on second resume — wrap with a one-shot flag so only the
            // first terminal callback resumes the continuation.
            let resumeBox = ResumeBox<PreparedShareAsset?>(continuation: continuation)

            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
            guard let asset = fetched.firstObject else {
                resumeBox.resume(with: nil)
                return
            }
            switch asset.mediaType {
            case .image:
                let opts = PHImageRequestOptions()
                opts.isNetworkAccessAllowed = true
                opts.deliveryMode = .highQualityFormat
                opts.isSynchronous = false
                opts.version = .current
                PHImageManager.default().requestImageDataAndOrientation(
                    for: asset,
                    options: opts
                ) { data, _, _, info in
                    // Ignore degraded-quality interim callbacks — only
                    // the final (non-degraded) one is the real deal.
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if isDegraded { return }
                    guard let data else {
                        resumeBox.resume(with: nil)
                        return
                    }
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent("beeclean_share_\(UUID().uuidString).jpg")
                    do {
                        try data.write(to: tmp)
                        resumeBox.resume(with: PreparedShareAsset(fileURL: tmp, isVideo: false))
                    } catch {
                        resumeBox.resume(with: nil)
                    }
                }
            case .video:
                let opts = PHVideoRequestOptions()
                opts.isNetworkAccessAllowed = true
                opts.deliveryMode = .highQualityFormat
                PHImageManager.default().requestAVAsset(
                    forVideo: asset,
                    options: opts
                ) { avAsset, _, _ in
                    if let urlAsset = avAsset as? AVURLAsset {
                        resumeBox.resume(with: PreparedShareAsset(fileURL: urlAsset.url, isVideo: true))
                    } else {
                        resumeBox.resume(with: nil)
                    }
                }
            default:
                resumeBox.resume(with: nil)
            }
        }
    }
}

/// One-shot continuation wrapper. PhotoKit callbacks fire 2+ times for
/// the same request (degraded + final, or success + progress). Without
/// this, a second resume on `CheckedContinuation` would trap.
private final class ResumeBox<T> {
    private var continuation: CheckedContinuation<T, Never>?
    private let lock = NSLock()

    init(continuation: CheckedContinuation<T, Never>) {
        self.continuation = continuation
    }

    func resume(with value: T) {
        lock.lock()
        let cont = continuation
        continuation = nil
        lock.unlock()
        cont?.resume(returning: value)
    }
}

// MARK: - UIActivityViewController bridge

private struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
