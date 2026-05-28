import SwiftUI

extension UnsubscribeListView {
    // MARK: - Header (matches CategoryDetailHeader layout)

    var header: some View {
        HStack(spacing: 14) {
            // Back chevron — circle
            Button {
                HapticManager.shared.arrowNudge(.backward)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: "F5F5F4"))
                    .clipShape(Circle())
            }

            // Icon + left-aligned title
            HStack(spacing: 6) {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "6366F1"))

                Text("Unsubscribe")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))
            }

            Spacer()

            // Unified Settings button — sleek solid black icon.
            // Opens the one sheet that contains both sort options AND
            // unsubscribe preferences.
            Button {
                HapticManager.shared.impact(.light)
                showSettings = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color(hex: "1C1917"))
                            .shadow(color: Color.black.opacity(0.18), radius: 8, y: 3)
                    )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Search Bar (matches CategoryDetailSearchBar)

    var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(.gray.opacity(0.6))

            TextField("Search senders…", text: $searchText)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "1C1917"))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { searchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: "F5F5F4"))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.05), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    // MARK: - Sort Row (used by unified Settings sheet)

    func sortRow(_ option: SortOption) -> some View {
        let isSelected = sortOption == option
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                sortOptionRaw = option.rawValue
            }
            HapticManager.shared.impact(.light)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: option.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? Color(hex: "1C1917") : Color(hex: "78716C"))
                    .frame(width: 24)

                Text(option.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? Color(hex: "1C1917") : Color(hex: "78716C"))

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "1C1917"))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color(hex: "F5F5F4") : Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(
                        isSelected ? Color(hex: "1C1917") : Color.black.opacity(0.06),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scanning Banner (live counter while loading)

    var scanningBanner: some View {
        HStack(spacing: 4) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .mutedForeground))
                .scaleEffect(0.6)

            Text("Scanning")
                .foregroundColor(.mutedForeground)

            Text(EmailFormatters.numFmt(displayedEmails))
                .foregroundColor(.foreground)
                .fontWeight(.semibold)
                .contentTransition(.numericText(countsDown: false))

            Text("emails from")
                .foregroundColor(.mutedForeground)

            Text(EmailFormatters.numFmt(displayedSenders))
                .foregroundColor(.foreground)
                .fontWeight(.semibold)
                .contentTransition(.numericText(countsDown: false))

            Text("senders")
                .foregroundColor(.mutedForeground)
        }
        .font(.system(size: 13, design: .rounded))
        .padding(.vertical, 10)
        .animation(.easeOut(duration: 0.3), value: displayedEmails)
        .animation(.easeOut(duration: 0.3), value: displayedSenders)
    }

    // MARK: - Settled Banner (scan complete)

    var settledBanner: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.success)

            Text("Found")
                .foregroundColor(.mutedForeground)

            Text(EmailFormatters.numFmt(emailService.totalSenderEmails))
                .foregroundColor(.foreground)
                .fontWeight(.semibold)

            Text("emails from")
                .foregroundColor(.mutedForeground)

            Text(EmailFormatters.numFmt(emailService.senders.count))
                .foregroundColor(.foreground)
                .fontWeight(.semibold)

            Text("senders")
                .foregroundColor(.mutedForeground)
        }
        .font(.system(size: 13, design: .rounded))
        .padding(.vertical, 10)
    }

    // MARK: - Content

    @ViewBuilder
    var senderContent: some View {
        if emailService.isSendersLoading && emailService.senders.isEmpty {
            loadingState
        } else if emailService.senders.isEmpty {
            emptyState
        } else {
            senderList
        }
    }

    // MARK: - Loading

    var loadingState: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                // Pulsing ring
                Circle()
                    .stroke(Color.primaryLight.opacity(0.15), lineWidth: 3)
                    .frame(width: 72, height: 72)

                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.primaryLight, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 72, height: 72)
                    .rotationEffect(.degrees(scanPhase == .waiting ? 0 : 360))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: scanPhase)

                Image(systemName: "envelope.open.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.primaryLight)
            }

            VStack(spacing: 6) {
                Text("Scanning your inbox")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.foreground)

                Text("Finding newsletters & promotions")
                    .font(.system(size: 14, design: .rounded))
                    .foregroundColor(.mutedForeground)
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Empty

    var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "envelope.open")
                .font(.system(size: 48))
                .foregroundColor(.mutedForeground)
            Text("No subscriptions found")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundColor(.foreground)
            Text("We couldn't find any newsletters or\npromotional senders in your inbox.")
                .font(.system(size: 14, design: .rounded))
                .foregroundColor(.mutedForeground)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - Sender List

    var senderList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 12) {
                ForEach(filteredSenders, id: \.email) { sender in
                    senderRow(sender)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .refreshable {
            await emailService.fetchSenders(scope: scope, refresh: true)
        }
    }

    @ViewBuilder
    func senderRow(_ sender: EmailSender) -> some View {
        SenderCard(
            sender: sender,
            isUnsubscribed: unsubscribedEmails.contains(sender.email),
            isKept: keptEmails.contains(sender.email),
            isLoading: isUnsubscribing == sender.email,
            onKeep: {
                let email = sender.email
                _ = withAnimation(.easeOut(duration: 0.2)) {
                    keptEmails.insert(email)
                }
                Task {
                    await emailService.keepSender(email: email)
                }
            },
            onUnsubscribe: {
                if skipConfirmation {
                    Task { await performUnsubscribe(from: sender, deleteExisting: confirmTrashExisting) }
                } else {
                    confirmSender = sender
                }
            }
        )
        .equatable()
    }

}
