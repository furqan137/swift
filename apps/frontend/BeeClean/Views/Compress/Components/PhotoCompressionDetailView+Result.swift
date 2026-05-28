import SwiftUI
import Photos

extension PhotoCompressionDetailView {

    // MARK: - Bee Commentary Row
    //
    // Compact: a small bee asset on the left + a clean speech bubble with
    // a randomized one-liner from the matching `BeeReaction` mood. Lives
    // above the summary box so the user reads a reaction first, then the
    // numbers.
    func beeCommentaryRow(result: CompressionResult) -> some View {
        let percent = result.didGrow ? 0 : result.savingsPercent
        let reaction = BeeReaction.pick(savingsPercent: percent, didGrow: result.didGrow)
        // Per-result seed so the bubble copy is stable across rerenders
        // but rotates between distinct compressions.
        let seed = result.outputURL.absoluteString.hashValue
        let line = reaction.line(seed: seed)

        return HStack(alignment: .center, spacing: 12) {
            Image(reaction.assetName)
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .rotationEffect(.degrees(beeBob * 4))
                .accessibilityHidden(true)

            speechBubble(line)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Sleek Summary Card
    //
    // Two-line summary inspired by the iOS Cleanup app:
    //   ✨  Compressed 1 Photo (X.X MB saved)
    //   ⏱  X% lighter than original
    //
    // followed by a muted footer note. Replaces the noisy honey hero so
    // the user can see the result at a glance and exit if they want.
    func sleekSummaryCard(result: CompressionResult) -> some View {
        let didGrow = result.didGrow
        let percent = didGrow ? 0 : result.savingsPercent

        return VStack(alignment: .leading, spacing: 14) {
            summaryRow(
                icon: "sparkles",
                iconColor: Color(hex: "F59E0B"),
                primary: "Compressed 1 Photo",
                accent: didGrow ? nil : "(\(result.formattedSavings) saved)"
            )

            summaryRow(
                icon: "hourglass",
                iconColor: Color(hex: "0A0A0A"),
                primary: didGrow ? "Already lean" : "\(percent)% lighter",
                accent: didGrow ? nil : "than original"
            )

            Divider()
                .background(Color(hex: "1C1917").opacity(0.06))

            HStack(spacing: 8) {
                Text(didGrow
                     ? "This image is already optimized — keep the original."
                     : "Save to Photos to keep the smaller version.")
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
        .opacity(beforeAfterOpacity)
    }

    func summaryRow(icon: String, iconColor: Color, primary: String, accent: String?) -> some View {
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

    // MARK: - Hero Photo Card

    func heroPhotoCard(result: CompressionResult) -> some View {
        let percent = result.didGrow ? 0 : result.savingsPercent
        let comment = beeCommentary(percent: percent, didGrow: result.didGrow)
        let useHoneyBee = percent >= 50

        return ZStack(alignment: .bottomLeading) {
            // Photo as the hero. No procedural overlays — the image is the
            // subject, the bee + bubble are guests.
            photoHeroBackground

            // Subtle bottom gradient for legibility, only where the bubble
            // and bee live. Photo above the band stays at full saturation.
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.0), location: 0.45),
                    .init(color: Color.black.opacity(0.16), location: 0.85),
                    .init(color: Color.black.opacity(0.28), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Speech bubble — sits above the bee with its tail pointing
            // down toward the bee's head. Mirrors the Bitepal pattern.
            speechBubble(comment)
                .padding(.leading, 84)
                .padding(.trailing, 16)
                .padding(.bottom, 86)

            // Bee mascot — peeks up from the bottom-left with a soft bob.
            // The honey-earned variant gets used at high savings; otherwise
            // we use the standard mascot so the celebration reads as
            // proportional to the result.
            Image(useHoneyBee ? "bee_stage4_honey_earned" : "bee_mascot")
                .resizable()
                .scaledToFit()
                .frame(width: 116, height: 116)
                .rotationEffect(.degrees(Double(-6 + beeBob * 6)))
                .offset(x: -10, y: 22 - beeBob * 4)
                .shadow(color: Color.black.opacity(0.22), radius: 10, x: 0, y: 6)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.10), radius: 20, x: 0, y: 8)
        .shadow(color: Color(hex: "FFC636").opacity(0.18), radius: 28, x: 0, y: 0)
        .offset(y: heroCardOffset)
        .opacity(heroCardOpacity)
    }

    var photoHeroBackground: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // While the thumbnail loads, show a warm honey wash so the
                // bee + bubble don't sit on plain gray for the few hundred
                // ms it takes the high-quality fetch to return.
                LinearGradient(
                    colors: [Color(hex: "FFE7B0"), Color(hex: "FFD37A")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(ProgressView().tint(Color(hex: "8B4513")))
            }
        }
    }

    func speechBubble(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(text)
                .font(.system(size: 15.5, weight: .heavy, design: .rounded))
                .foregroundColor(Color(hex: "1C1917"))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 4)
                )

            // Triangular tail glued to the bottom-left so the bubble reads
            // as something the bee just said. The slight upward offset
            // hides the seam between bubble body and tail.
            HStack(spacing: 0) {
                BubbleTail()
                    .fill(Color.white)
                    .frame(width: 18, height: 12)
                    .padding(.leading, 22)
                    .shadow(color: Color.black.opacity(0.14), radius: 6, y: 4)
                Spacer(minLength: 0)
            }
            .offset(y: -1)
        }
    }

    /// Picks a kawaii one-liner for the bee to deliver based on how much
    /// space we saved. Each tier maps to a distinctly-felt moment so a
    /// repeat user notices the bee react differently to a 12% trim vs a
    /// 92% trim. `didGrow` (compressed file ended up bigger than the
    /// source — happens with already-tiny inputs) gets its own line so we
    /// never lie and claim savings that don't exist.
    func beeCommentary(percent: Int, didGrow: Bool) -> String {
        if didGrow { return "Already at peak buzz! Nothing left to trim." }
        switch percent {
        case 90...:        return "Whoa! Practically vapor — \(percent)% gone! 🍯"
        case 70..<90:      return "Sweet! \(percent)% lighter. Honey on a diet."
        case 50..<70:      return "Halved! Light as a wing-flap now."
        case 30..<50:      return "Nice — \(percent)% off. Real bite outta this one."
        case 10..<30:      return "Every byte counts in the hive. \(percent)% saved!"
        default:           return "Already lean — barely a crumb to shed."
        }
    }

    // MARK: - Summary Card

    func summaryCard(result: CompressionResult) -> some View {
        let percent = result.didGrow ? 0 : result.savingsPercent

        return VStack(alignment: .leading, spacing: 16) {
            // Headline: percent + "lighter" — counts up animated
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(result.didGrow ? "No change" : "Compressed")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "8A8A8E"))
                    Spacer()
                    if !result.didGrow {
                        freedBadge(result.formattedSavings)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("\(percentDisplay)")
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundColor(Color(hex: "1C1917"))
                        .contentTransition(.numericText(countsDown: false))
                    Text("%")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundColor(Color(hex: "1C1917"))
                        .baselineOffset(8)
                        .padding(.leading, 1)
                    Text(result.didGrow ? " same size" : " lighter")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "8A8A8E"))
                        .padding(.leading, 6)
                }
            }

            // Compression bar — honey-gradient fill animates from 0 to %
            compressionBar(percent: percent)

            // Before/After block + format chips on the same line
            HStack(alignment: .center, spacing: 12) {
                sizeBlock(label: "Before", value: result.formattedOriginalSize, color: Color(hex: "8A8A8E"))
                arrowChip
                sizeBlock(label: "After", value: result.formattedCompressedSize, color: Color(hex: "1C1917"))
                Spacer(minLength: 0)
            }

            // Metadata pills — codec, resolution, encode time
            HStack(spacing: 6) {
                metadataPill(icon: "doc.fill", text: result.codec)
                metadataPill(icon: "aspectratio.fill", text: result.outputResolution)
                metadataPill(icon: "timer", text: result.formattedTime)
                Spacer(minLength: 0)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 14, x: 0, y: 4)
        )
        .opacity(beforeAfterOpacity)
    }

    func compressionBar(percent: Int) -> some View {
        // Bar fills proportionally to `percentDisplay` so the visual ticks
        // up alongside the headline number — same drumbeat, two surfaces.
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(hex: "F4F4F5"))

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "FFC636"), Color(hex: "F5A623")],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(0, geo.size.width * CGFloat(percentDisplay) / 100.0))
                    .animation(.easeOut(duration: 0.18), value: percentDisplay)
            }
        }
        .frame(height: 14)
    }

    func sizeBlock(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "A8A29E"))
                .textCase(.uppercase)
                .tracking(0.6)
            Text(value)
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundColor(color)
        }
    }

    var arrowChip: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 11, weight: .black))
            .foregroundColor(Color(hex: "C4850A"))
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color(hex: "FFF3C4")))
    }

    func freedBadge(_ savings: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 10, weight: .bold))
            Text(savings + " freed")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .foregroundColor(Color(hex: "047857"))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color(hex: "ECFDF5")))
    }

    func metadataPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundColor(Color(hex: "78716C"))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(Color(hex: "F5F5F4"))
        )
    }

    // MARK: - Action Stack

    func resultActionStack(result: CompressionResult) -> some View {
        VStack(spacing: 10) {
            primaryActionButton(title: "Save to Photos", iconName: "square.and.arrow.down.fill") {
                HapticManager.shared.impact(.light)
                if SubscriptionService.shared.isPro {
                    let compressionResult = result
                    Task {
                        await actionFlow.execute(section: .compress, actionType: .compress, itemCount: 1) {
                            let saved = await engine.savePhotoToPhotoLibrary(url: compressionResult.outputURL)
                            guard saved else { throw NSError(domain: "CompressionSave", code: -1) }
                            await MainActor.run {
                                HiveStatsManager.shared.recordCleanup(
                                    action: "compression",
                                    itemCount: 1,
                                    bytesSaved: Int64(compressionResult.savings),
                                    category: .photoCompression
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
            }

            if !originalDeleted, !result.didGrow {
                secondaryActionButton(title: "Save & Replace Original") {
                    HapticManager.shared.impact(.light)
                    Task {
                        let saved = await engine.savePhotoToPhotoLibrary(url: result.outputURL)
                        if saved {
                            showDeleteConfirm = true
                        } else {
                            presentSaveError("Couldn't save to your library. Check Photos permission in Settings.")
                        }
                    }
                }
            } else if originalDeleted {
                replacedConfirmation(savings: result.savings)
            }
        }
    }

    func primaryActionButton(title: String, iconName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 15, weight: .heavy))
                Text(title)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: "3D2914"), Color(hex: "1C1917")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        // A thin honey rim along the top edge so the button
                        // reads as part of the bee/honey world, not a
                        // default iOS black pill.
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [Color(hex: "FFC636").opacity(0.7), Color.clear],
                                    startPoint: .top,
                                    endPoint: .center
                                ),
                                lineWidth: 1
                            )
                    )
            )
            .shadow(color: Color(hex: "1C1917").opacity(0.22), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(ScaleButtonStyle())
    }

    func secondaryActionButton(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundColor(Color(hex: "8B4513"))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: "FFF3C4").opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color(hex: "F5CC4A").opacity(0.5), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }

    func replacedConfirmation(savings: Int64) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
            Text("Replaced · \(formatBytes(savings)) freed")
                .font(.system(size: 14, weight: .bold, design: .rounded))
        }
        .foregroundColor(Color(hex: "8B4513"))
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "FFF3C4").opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color(hex: "F5CC4A").opacity(0.5), lineWidth: 1)
                )
        )
    }

    // MARK: - Result Animation

    /// Choreographs the celebration: hero swoops up, bee bobs, percent counts
    /// up from 0 to the final value, sparkles start orbiting, metadata and
    /// actions fade up last. Stagger keeps each element distinctly felt.
    func playResultAnimation(savingsPercent: Int) {
        HapticManager.shared.compressionComplete()

        // 1. Hero swoop
        withAnimation(.spring(response: 0.55, dampingFraction: 0.78)) {
            heroCardOffset = 0
            heroCardOpacity = 1.0
        }

        // 2. Count the percent number up in parallel with the swoop
        animatePercent(to: savingsPercent)

        // 3. Before/After strip + metadata
        withAnimation(.easeOut(duration: 0.4).delay(0.35)) {
            beforeAfterOpacity = 1.0
        }

        // 4. Actions slide up last
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.55)) {
            resultActionsOffset = 0
            resultActionsOpacity = 1.0
        }

        // 5. Start a continuous bee bob
        withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true).delay(0.3)) {
            beeBob = 1.0
        }
    }

    /// Number counter that tweens via Timer so we can drive the
    /// `.numericText` content transition on a plain `Int` state.
    func animatePercent(to target: Int) {
        percentDisplay = 0
        guard target > 0 else { return }
        let totalDuration: TimeInterval = 0.9
        let stepCount = max(target, 1)
        let stepDelay = totalDuration / Double(stepCount)

        for i in 1...target {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDelay * Double(i) + 0.1) {
                withAnimation(.easeOut(duration: stepDelay * 1.2)) {
                    percentDisplay = i
                }
            }
        }
    }

}

