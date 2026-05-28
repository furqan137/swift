import SwiftUI
import AVKit

extension CompressionDetailView {

    // MARK: - Setup Screen

    var setupScreen: some View {
        // Explicit width pinned from screen bounds — same fix as Photo
        // setup screen. `.frame(maxWidth: .infinity)` was unreliable in
        // this layout context.
        VStack(spacing: 0) {
            let cardWidth = UIScreen.main.bounds.width - 40
            // Mirror the Cleanup video experience: native AVPlayerViewController
            // with the system playback chrome. Once a player is loaded, users
            // get the full-screen toggle, scrubber, mute, AirPlay, and PiP for
            // free instead of a binary tap-to-play that hides every other
            // control. The thumbnail with the round play button stays as the
            // pre-load affordance so the screen never feels empty while
            // PHImageManager fetches the playable URL.
            ZStack {
                if isPlayingInline, let player = inlinePlayer {
                    CompressInlineVideoPlayer(player: player)
                        .frame(width: cardWidth, height: Self.previewCardHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                } else {
                    Button {
                        if video.asset != nil {
                            HapticManager.shared.impact(.light)
                            Task { await playInline() }
                        }
                    } label: {
                        ZStack {
                            if let thumbnail = thumbnail {
                                Image(uiImage: thumbnail)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } else {
                                Color(hex: "E8E4DF")
                                    .overlay(ProgressView().tint(Color(hex: "A1A1AA")))
                            }

                            if video.asset != nil {
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .frame(width: 60, height: 60)
                                    .overlay(
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(.white)
                                            .offset(x: 2)
                                    )
                                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                            }
                        }
                        .frame(width: cardWidth, height: Self.previewCardHeight)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)

            Spacer()

            bitepalControlPanel(
                sizeBefore: formatBytes(video.fileSize),
                sizeAfter: formatBytes(estimatedSize),
                savings: formatBytes(estimatedSavings),
                deleteLabel: "Delete Video",
                onStart: {
                    // `primaryCommit()` — kicking off the compression
                    // pipeline is a real submit action, not a generic
                    // tap. Replaces the raw `impact(.medium)` so the
                    // tactile read matches the moment ("we're going").
                    HapticManager.shared.primaryCommit()
                    if let asset = video.asset {
                        Task { await engine.compressVideo(phAsset: asset, level: selectedLevel) }
                    }
                },
                onDelete: {
                    HapticManager.shared.impact(.light)
                    showDeleteOnlyConfirm = true
                }
            )
        }
    }

    /// Fixed height for the preview card. Trimmed from 420 to 360 so
    /// landscape videos crop less aggressively and the bottom panel
    /// has more breathing room. Matches the photo flow.
    static let previewCardHeight: CGFloat = 360

    /// Before/After size column used in the size-comparison row.
    func sizeColumn(label: String, value: String, valueColor: Color, alignment: HorizontalAlignment = .center) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text(label)
                .font(.custom("Poppins-Bold", size: 11))
                .foregroundColor(Color(hex: "9CA3AF"))
                .textCase(.uppercase)
                .tracking(1.2)
            Text(value)
                .font(.custom("Poppins-Bold", size: 28))
                .foregroundColor(valueColor)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : (alignment == .trailing ? .trailing : .center))
    }

    /// Before/After row — bold typography flanking a solid ink arrow chip
    /// (mirrors Photo Compress).
    func sizeComparisonRow(before: String, after: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            sizeColumn(
                label: "Before",
                value: before,
                valueColor: Color(hex: "1C1917"),
                alignment: .leading
            )

            Image(systemName: "arrow.right")
                .font(.system(size: 15, weight: .black))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Color(hex: "0A0A0A")))
                .shadow(color: Color.black.opacity(0.20), radius: 8, y: 3)

            sizeColumn(
                label: "After",
                value: after,
                valueColor: Color(hex: "0A0A0A"),
                alignment: .trailing
            )
        }
    }

    func levelChip(_ level: CompressionLevel) -> some View {
        let isSelected = selectedLevel == level
        let pct = level.displayPercent

        return Button {
            HapticManager.shared.impact(.light)
            selectedLevel = level
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(level.rawValue)
                    .font(.custom("Poppins-Bold", size: 14))
                Text("\(pct)% smaller")
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.78)
            }
            .foregroundColor(isSelected ? .white : Color(hex: "0A0A0A"))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(BitepalChipBackground(isSelected: isSelected))
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.18), value: isSelected)
    }

    // MARK: - Bitepal Control Panel
    //
    // Clean white card on the cool Bitepal canvas. No glass, no sheen —
    // mirrors PhotoCompressionDetailView so the two flows stay in sync.
    func bitepalControlPanel(
        sizeBefore: String,
        sizeAfter: String,
        savings: String,
        deleteLabel: String,
        onStart: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 16) {
            sizeComparisonRow(before: sizeBefore, after: sizeAfter)

            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Save \(savings)")
                    .font(.custom("Poppins-SemiBold", size: 12))
            }
            .foregroundColor(Color(hex: "047857"))
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color(hex: "ECFDF5")))

            HStack(spacing: 8) {
                ForEach(CompressionLevel.allCases) { level in
                    levelChip(level)
                }
            }

            Button(action: onStart) {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 15, weight: .heavy))
                    Text("Start Compress")
                        .font(.custom("Poppins-Bold", size: 17))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(BitepalPrimaryButtonBackground())
            }
            .buttonStyle(ScaleButtonStyle())

            // Sleek ghost-style destructive — outlined hairline capsule
            // with a single thin trash glyph. The previous candy-pink fill
            // read as gimmicky next to the espresso primary CTA; this
            // muted treatment lets the button stay legibly destructive
            // (warm crimson text + glyph) without shouting.
            Button(action: onDelete) {
                HStack(spacing: 7) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                    Text(deleteLabel)
                        .font(.custom("Poppins-SemiBold", size: 14))
                }
                .foregroundColor(Color(hex: "B91C1C"))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Capsule()
                        .fill(Color.clear)
                        .overlay(
                            Capsule()
                                .stroke(Color(hex: "B91C1C").opacity(0.18), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.10), radius: 28, y: -4)
                .shadow(color: Color.black.opacity(0.04), radius: 4, y: -1)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Progress Screen

    var progressScreen: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 200, height: 200)

                Circle()
                    .stroke(Color(hex: "F5F5F4"), lineWidth: 6)
                    .frame(width: 160, height: 160)

                Circle()
                    .trim(from: 0, to: CGFloat(activeProgress))
                    .stroke(
                        Color(hex: "1C1917"),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 160, height: 160)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: activeProgress)

                VStack(spacing: 4) {
                    Text("\(Int(activeProgress * 100))%")
                        .font(.custom("Poppins-Bold", size: 40))
                        .foregroundColor(Color(hex: "1C1917"))
                        .contentTransition(.numericText(countsDown: false))

                    Text(activePhase.rawValue)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(Color(hex: "8A8A8E"))
                }
            }

            Spacer()

            Button {
                engine.cancel()
            } label: {
                Text("Cancel")
                    .font(.custom("Poppins-SemiBold", size: 15))
                    .foregroundColor(Color(hex: "1C1917"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

}
