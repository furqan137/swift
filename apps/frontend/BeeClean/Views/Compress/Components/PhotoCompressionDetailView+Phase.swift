import SwiftUI
import Photos

extension PhotoCompressionDetailView {

    // MARK: - Setup Screen

    var setupScreen: some View {
        // Explicit width derived from screen bounds — `.frame(maxWidth:
        // .infinity)` was unreliable here (photo card was rendering
        // edge-to-edge with no padding). Hard-pinning width makes the
        // layout deterministic.
        VStack(spacing: 0) {
            let cardWidth = UIScreen.main.bounds.width - 40
            // Tap-to-zoom — opens the shared `ZoomablePreviewOverlay`
            // (pinch / double-tap / pan / tap-to-dismiss) so the user can
            // inspect the photo at full resolution before compressing,
            // matching Apple Photos' tap-into-thumbnail affordance.
            // `buttonStyle(.plain)` so the photo stays full-color (no
            // blue tint) and `contentShape` so the whole rounded rect is
            // hittable, including the empty corners between the image
            // and the rounded mask.
            Button {
                HapticManager.shared.impact(.light)
                showFullScreenPreview = true
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
                }
                .frame(width: cardWidth, height: Self.previewCardHeight)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .contentShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()

            bitepalControlPanel(
                sizeBefore: formatBytes(photo.fileSize),
                sizeAfter: formatBytes(estimatedSize),
                savings: formatBytes(estimatedSavings),
                deleteLabel: "Delete Photo",
                onStart: {
                    HapticManager.shared.impact(.medium)
                    if let asset = photo.asset {
                        Task { await engine.compressPhoto(phAsset: asset, level: selectedLevel) }
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
    /// landscape photos crop less aggressively (less zoomed-in feel) and
    /// the bottom panel has more breathing room above it.
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
    /// so the size delta reads as the focal point of the control panel.
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
        let pct = level.photoDisplayPercent

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
    // Clean white card on the cool Bitepal canvas. No glass blur, no
    // sheen — flat surface with one soft drop shadow. Shared layout for
    // Photo and Video compress.
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

            // Savings pill — flat mint, no border
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

            // Level picker — Bitepal pills
            HStack(spacing: 8) {
                ForEach(CompressionLevel.allCases) { level in
                    levelChip(level)
                }
            }

            // Start button — bigger, more presence
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

    // MARK: - Result Screen — Bitepal-mirrored celebration
    //
    // Layout, top to bottom:
    //   1. The user's actual photo as a hero card (no painted overlay) with
    //      the bee peeking up from the bottom-left and a speech bubble
    //      delivering kawaii commentary on how the compression went.
    //   2. A clean white summary card with the percent saved, an animated
    //      compression bar, before/after sizes, the freed-bytes badge, and
    //      format/resolution/time pills — every stat the old layout buried
    //      in two sparse rows separated by an empty white expanse.
    //   3. The save / replace actions, anchored to the bottom of the screen.
    //
    // The redesign mirrors Bitepal's meal detail screen exactly while
    // staying inside our cartoon/kawaii bee aesthetic and not painting on
    // top of the user's image.

    func resultScreen(_ result: CompressionResult) -> some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 18) {
                    beeCommentaryRow(result: result)
                        .padding(.horizontal, 18)
                        .padding(.top, 14)

                    sleekSummaryCard(result: result)
                        .padding(.horizontal, 18)
                }
                .padding(.bottom, 24)
            }

            resultActionStack(result: result)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .offset(y: resultActionsOffset)
                .opacity(resultActionsOpacity)
        }
        .onAppear { playResultAnimation(savingsPercent: result.didGrow ? 0 : result.savingsPercent) }
    }

}

