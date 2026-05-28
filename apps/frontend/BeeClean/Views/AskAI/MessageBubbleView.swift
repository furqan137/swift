import SwiftUI

// MARK: - Message Bubble (iMessage-style)
struct MessageBubbleView: View {
    let message: AIMessage
    var showTail: Bool = true
    var onGridTap: (() -> Void)?
    var onRetry: (() -> Void)?

    private var screenWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 393
    }
    private var maxBubbleWidth: CGFloat { screenWidth * 0.75 }
    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
    ]
    private let maxInlinePhotos = 6

    var body: some View {
        let isUser = message.role == .user
        let tailRadius: CGFloat = showTail ? 4 : 18
        let hasResults = message.assetIds != nil

        HStack {
            if isUser { Spacer(minLength: 0) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // User messages: simple text bubble
                if isUser {
                    Text(message.content)
                        .font(.system(size: 17))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(userBubbleBackground(tailRadius: tailRadius))
                }
                // Assistant messages: state-driven rendering
                else {
                    assistantContent
                        .background(assistantBubbleBackground(tailRadius: tailRadius))
                }
            }
            .frame(maxWidth: hasResults ? screenWidth * 0.85 : maxBubbleWidth,
                   alignment: isUser ? .trailing : .leading)

            if !isUser { Spacer(minLength: 0) }
        }
        .onAppear {
            // Soft "the answer arrived" landing for assistant replies —
            // the headline beat of the AskBee haptic rhythm. Gated to:
            //   • assistant role
            //   • .complete state (skips loading placeholders + .failed)
            //   • non-empty content
            //   • fresh timestamp (within 3 s of now)
            //
            // The timestamp guard is what makes this safe inside the
            // chat's LazyVStack: scrolling an old message back into
            // view recycles the bubble and re-fires .onAppear, but its
            // timestamp is stale so we silently skip. Only a genuinely
            // just-arrived reply trips the haptic.
            guard !isUser,
                  message.state == .complete,
                  !message.content.isEmpty,
                  Date().timeIntervalSince(message.timestamp) < 3
            else { return }
            HapticManager.shared.replyLanded()
        }
    }

    // MARK: - Background Helpers

    private func userBubbleBackground(tailRadius: CGFloat) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: 18,
            bottomTrailingRadius: tailRadius,
            topTrailingRadius: 18,
            style: .continuous
        )
        .fill(Color(hex: "007AFF"))
    }

    private func assistantBubbleBackground(tailRadius: CGFloat) -> some View {
        UnevenRoundedRectangle(
            topLeadingRadius: 18,
            bottomLeadingRadius: tailRadius,
            bottomTrailingRadius: 18,
            topTrailingRadius: 18,
            style: .continuous
        )
        .fill(Color.white)
    }

    // MARK: - Assistant Content

    @ViewBuilder
    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch message.state {
            case .loading:
                // Typing indicator for all loading messages
                TypingIndicatorView()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                // Skeleton grid ONLY for photo searches (messages with actions)
                // Conversation and follow-up queries have no actions, so no skeleton
                if !message.actions.isEmpty {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(0..<3, id: \.self) { _ in
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color(hex: "F4F4F5"))
                                )
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
                }

            case .complete:
                // Reply + results both ready
                if !message.content.isEmpty {
                    Text(message.content)
                        .font(.system(size: 17))
                        .foregroundColor(Color(hex: "1C1917"))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                }

                if let assetIds = message.assetIds {
                    if assetIds.isEmpty {
                        emptyResultsView
                    } else {
                        inlinePhotoGrid(assetIds: assetIds)
                            .padding(.horizontal, 6)
                            .padding(.bottom, 6)
                    }
                }

            case .failed(let error):
                // Error state with styled retry button
                VStack(alignment: .leading, spacing: 12) {
                    Text(error)
                        .font(.system(size: 15))
                        .foregroundColor(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 10)

                    Button {
                        HapticManager.shared.impact(.medium, intensity: 0.7)
                        onRetry?()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 13, weight: .medium))
                            Text(BCLoc.retry.tr)
                                .font(.system(size: 15, weight: .medium))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(hex: "1C1917"))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }
            }
        }
    }

    // MARK: - Empty Results Helper

    private var emptyResultsView: some View {
        HStack(spacing: 6) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 13))
                .foregroundColor(Color(hex: "A1A1AA"))
            Text("No matching photos found")
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "A1A1AA"))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private func inlinePhotoGrid(assetIds: [String]) -> some View {
        let visibleIds = Array(assetIds.prefix(maxInlinePhotos))
        let remaining = assetIds.count - maxInlinePhotos

        Button {
            // The bubble's mini-grid is a navigation surface — tapping
            // pushes the expanded results view. tapSensation pairs the
            // click with the push, so the user feels the consequence
            // of the tap as the new view animates in.
            HapticManager.shared.tapSensation()
            onGridTap?()
        } label: {
            LazyVGrid(columns: gridColumns, spacing: 2) {
                ForEach(Array(visibleIds.enumerated()), id: \.element) { index, assetId in
                    let isLastCell = index == visibleIds.count - 1 && remaining > 0

                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay(
                            PhotoThumbnailView(
                                assetIdentifier: assetId,
                                size: CGSize(width: 200, height: 200)
                            )
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            Group {
                                if isLastCell {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.black.opacity(0.5))
                                    Text("+\(remaining)")
                                        .font(.system(size: 16, weight: .bold))
                                        .foregroundColor(.white)
                                }
                            }
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }
}
