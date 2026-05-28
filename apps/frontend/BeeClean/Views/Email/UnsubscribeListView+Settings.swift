import SwiftUI

extension UnsubscribeListView {
    // MARK: - Unified Settings Sheet (Sort + Preferences, light mode)

    var unsubscribeSettingsSheet: some View {
        VStack(spacing: 0) {
            // Drag handle
            Capsule()
                .fill(Color(hex: "D4D4D8"))
                .frame(width: 40, height: 5)
                .padding(.top, 12)
                .padding(.bottom, 16)

            Text("Unsubscribe Settings")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(Color(hex: "1C1917"))
                .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    // ── Sort Section ──────────────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("SORT SENDERS BY")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                            .foregroundColor(Color(hex: "A1A1AA"))
                            .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            ForEach(SortOption.allCases) { option in
                                sortRow(option)
                            }
                        }
                    }

                    // ── Preferences Section ───────────────────────
                    VStack(alignment: .leading, spacing: 10) {
                        Text("PREFERENCES")
                            .font(.system(size: 11, weight: .heavy, design: .rounded))
                            .tracking(1.2)
                            .foregroundColor(Color(hex: "A1A1AA"))
                            .padding(.horizontal, 4)

                        VStack(spacing: 8) {
                            settingsToggleRow(
                                text: "Automatically move emails to Trash",
                                isOn: $confirmTrashExisting
                            )
                            settingsToggleRow(
                                text: "Do not ask for confirmation",
                                isOn: $skipConfirmation
                            )
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            // Apply button — solid black (light theme), full width
            Button {
                HapticManager.shared.impact(.light)
                showSettings = false
            } label: {
                Text(BCLoc.apply.tr)
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(hex: "1C1917"))
                            .shadow(color: Color.black.opacity(0.15), radius: 12, y: 6)
                    )
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 10)

            Button {
                showSettings = false
            } label: {
                Text("Cancel")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "78716C"))
            }
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
    }

    func settingsToggleRow(text: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isOn.wrappedValue.toggle() }
            HapticManager.shared.impact(.light)
        } label: {
            HStack(spacing: 12) {
                Text(text)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(Color(hex: "1C1917"))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(
                            isOn.wrappedValue
                                ? Color(hex: "1C1917")
                                : Color.black.opacity(0.20),
                            lineWidth: 1.8
                        )
                        .frame(width: 26, height: 26)

                    if isOn.wrappedValue {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(hex: "1C1917"))
                            .frame(width: 26, height: 26)

                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(hex: "F5F5F4"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scanning Animation

    func startScanAnimation() {
        // Start with small realistic numbers
        displayedEmails = Int.random(in: 80...200)
        displayedSenders = Int.random(in: 10...25)
        scanPhase = .waiting

        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            Task { @MainActor in
                // Bail if the view dismissed between this tick being
                // scheduled and the Task actually running on main. The
                // 0.2s cadence + per-tick Task spawn meant a
                // backgrounded scan could keep pushing work onto the
                // main queue for a while after dismiss; checking
                // `scanTimer == nil` (cleared in .onDisappear) gates
                // every cycle on the view still being mounted.
                guard scanTimer != nil else { return }
                let realEmails = emailService.totalSenderEmails
                let realSenders = emailService.senders.count
                let hasRealData = realSenders > 0

                switch scanPhase {
                case .waiting:
                    // Increment slowly but STOP at realistic ceiling
                    if displayedEmails < maxFakeEmails {
                        withAnimation(.easeOut(duration: 0.25)) {
                            // Slow down as we approach the ceiling
                            let remaining = maxFakeEmails - displayedEmails
                            let emailStep = min(Int.random(in: 20...80), remaining)
                            displayedEmails += emailStep
                        }
                    }
                    if displayedSenders < maxFakeSenders {
                        withAnimation(.easeOut(duration: 0.25)) {
                            let remaining = maxFakeSenders - displayedSenders
                            let senderStep = min(Int.random(in: 1...4), remaining)
                            displayedSenders += senderStep
                        }
                    }

                    // If real data arrived, switch to syncing
                    if hasRealData {
                        scanPhase = .syncing
                    }

                case .syncing:
                    let emailDiff = realEmails - displayedEmails
                    let senderDiff = realSenders - displayedSenders

                    // Close enough — snap to final
                    if abs(emailDiff) <= 10 && abs(senderDiff) <= 2 {
                        withAnimation(.easeOut(duration: 0.4)) {
                            displayedEmails = realEmails
                            displayedSenders = realSenders
                        }
                        scanPhase = .done
                        scanTimer?.invalidate()
                    } else {
                        // Converge toward real numbers (works for both up and down)
                        withAnimation(.easeOut(duration: 0.25)) {
                            let step = max(1, abs(emailDiff) / 5)
                            displayedEmails += emailDiff > 0 ? step : -step

                            let sStep = max(1, abs(senderDiff) / 4)
                            displayedSenders += senderDiff > 0 ? sStep : -sStep
                        }
                    }

                case .done:
                    scanTimer?.invalidate()
                }
            }
        }
    }

    func syncToRealNumbers() {
        let realEmails = emailService.totalSenderEmails
        let realSenders = emailService.senders.count
        guard realSenders > 0 && !emailService.isSendersLoading else { return }

        // If timer is still running, let it handle the sync
        if scanPhase == .waiting {
            scanPhase = .syncing
        } else if scanPhase == .done || scanTimer == nil {
            // Timer already stopped — snap directly
            withAnimation(.easeOut(duration: 0.5)) {
                displayedEmails = realEmails
                displayedSenders = realSenders
            }
            scanPhase = .done
        }
    }

}
