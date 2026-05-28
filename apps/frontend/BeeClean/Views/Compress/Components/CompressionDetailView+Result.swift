import SwiftUI

extension CompressionDetailView {

    // MARK: - Result Screen — bee commentary + sleek summary card

    func resultScreen(_ result: CompressionResult) -> some View {
        VStack(spacing: 18) {
            beeCommentaryRow(result: result)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .opacity(resultStatsOpacity)

            sleekSummaryCard(result: result)
                .padding(.horizontal, 18)
                .opacity(resultStatsOpacity)

            Spacer()

            // Actions
            VStack(spacing: 10) {
                // Save to Camera Roll
                Button {
                    // `actionSuccess()` — the user is committing the
                    // win, which deserves a positive notify cue (not
                    // a flat light impact).
                    HapticManager.shared.actionSuccess()
                    if SubscriptionService.shared.isPro {
                        let compressionResult = result
                        Task {
                            await actionFlow.execute(section: .compress, actionType: .compress, itemCount: 1) {
                                let saved = await engine.saveToPhotoLibrary(url: compressionResult.outputURL)
                                guard saved else { throw NSError(domain: "CompressionSave", code: -1) }
                                // Wire compression into the Progress
                                // lifetime stats. Without this, the
                                // Progress chart + Recent Wins counters
                                // never reflect compressed bytes — the
                                // `recordCleanup(action: "compression", ...)`
                                // tag is exactly what HiveStatsManager
                                // expects for this flow.
                                await MainActor.run {
                                    HiveStatsManager.shared.recordCleanup(
                                        action: "compression",
                                        itemCount: 1,
                                        bytesSaved: Int64(compressionResult.savings),
                                        category: .videoCompression
                                    )
                                }
                                return ActionResult(
                                    section: .compress, actionType: .compress,
                                    itemsProcessed: 1, bytesFreed: nil,
                                    bytesSaved: compressionResult.savings,
                                    originalBytes: compressionResult.originalSize,
                                    compressedBytes: compressionResult.compressedSize,
                                    timestamp: Date(), breakdown: nil, topSenders: nil
                                )
                            }
                        }
                    } else {
                        pendingSaveURL = result.outputURL
                        showCompressGate = true
                    }
                } label: {
                    Text("Save to Camera Roll")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color(hex: "1C1917"))
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
                }
                .buttonStyle(ScaleButtonStyle())

                // Save & Replace (only when compression actually saved space)
                if !originalDeleted, !result.didGrow {
                    Button {
                        HapticManager.shared.actionSuccess()
                        Task {
                            let saved = await engine.saveToPhotoLibrary(url: result.outputURL)
                            if saved { showDeleteConfirm = true }
                        }
                    } label: {
                        Text("Save & Replace Original")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundColor(Color(hex: "22C55E"))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(Color(hex: "22C55E").opacity(0.06))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(Color(hex: "22C55E").opacity(0.15), lineWidth: 0.5)
                                    )
                            )
                    }
                } else if originalDeleted {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                        Text("Replaced · \(formatBytes(result.savings)) freed")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(Color(hex: "22C55E"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: "22C55E").opacity(0.06))
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            .offset(y: resultActionsOffset)
            .opacity(resultActionsOpacity)
        }
        .onAppear { playResultAnimation() }
    }

    // MARK: - Bee Commentary Row (mirrors PhotoCompressionDetailView)
    func beeCommentaryRow(result: CompressionResult) -> some View {
        let percent = result.didGrow ? 0 : result.savingsPercent
        let reaction = BeeReaction.pick(savingsPercent: percent, didGrow: result.didGrow)
        let seed = result.outputURL.absoluteString.hashValue
        let line = reaction.line(seed: seed)

        return HStack(alignment: .center, spacing: 12) {
            Image(reaction.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            videoSpeechBubble(line)

            Spacer(minLength: 0)
        }
    }

    func videoSpeechBubble(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14.5, weight: .heavy, design: .rounded))
            .foregroundColor(Color(hex: "1C1917"))
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: Color.black.opacity(0.10), radius: 10, y: 3)
            )
    }

    // MARK: - Sleek Summary Card (mirrors PhotoCompressionDetailView)
    func sleekSummaryCard(result: CompressionResult) -> some View {
        let didGrow = result.didGrow
        let percent = didGrow ? 0 : result.savingsPercent

        return VStack(alignment: .leading, spacing: 14) {
            videoSummaryRow(
                icon: "sparkles",
                iconColor: Color(hex: "F59E0B"),
                primary: "Compressed 1 Video",
                accent: didGrow ? nil : "(\(formatBytes(result.savings)) saved)"
            )

            videoSummaryRow(
                icon: "hourglass",
                iconColor: Color(hex: "0A0A0A"),
                primary: didGrow ? "Already lean" : "\(percent)% lighter",
                accent: didGrow ? nil : "than original"
            )

            Divider().background(Color(hex: "1C1917").opacity(0.06))

            HStack(spacing: 8) {
                Text(didGrow
                     ? "This video is already optimized — keep the original."
                     : "Save to Camera Roll to keep the smaller version.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "78716C"))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.06), radius: 18, y: 6)
        )
    }

    func videoSummaryRow(icon: String, iconColor: Color, primary: String, accent: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .heavy))
                .foregroundColor(iconColor)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(primary)
                    .font(.custom("Poppins-Bold", size: 19))
                    .foregroundColor(Color(hex: "1C1917"))
                if let accent {
                    Text(accent)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "0A0A0A").opacity(0.55))
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Result Animation

    func playResultAnimation() {
        // Fire the compression-complete haptic
        HapticManager.shared.compressionComplete()

        // Step 1: Ring draws in (0.0s)
        withAnimation(.easeOut(duration: 0.6)) {
            resultRingProgress = 1.0
        }

        // Step 2: Checkmark bounces in (0.3s)
        withAnimation(.spring(response: 0.45, dampingFraction: 0.55).delay(0.3)) {
            resultCheckScale = 1.0
            resultCheckOpacity = 1.0
        }

        // Step 3: Title fades in (0.5s)
        withAnimation(.easeOut(duration: 0.35).delay(0.5)) {
            resultTextOpacity = 1.0
        }

        // Step 4: Stats card fades in (0.65s)
        withAnimation(.easeOut(duration: 0.35).delay(0.65)) {
            resultStatsOpacity = 1.0
        }

        // Step 5: Action buttons slide up (0.8s)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.8)) {
            resultActionsOffset = 0
            resultActionsOpacity = 1.0
        }
    }

}
