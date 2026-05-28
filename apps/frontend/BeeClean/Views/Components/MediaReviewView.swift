import SwiftUI

/// Generic review view for any media type (screenshots, photos, recordings).
/// Replaces 4 identical review views with one parameterized by MediaSwipeViewModel.
struct MediaReviewView: View {
    @ObservedObject var vm: MediaSwipeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirm = false
    let onDeleteComplete: () -> Void

    private var markedItems: [ScreenshotAsset] {
        vm.items.filter { vm.markedForDeletion.contains($0.assetId) }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    // Light-mode palette — matches the Contacts redesign: white cards on
    // cream, warm honey-tinted shadow, espresso text.
    private static let cardText    = Color(hex: "1C1917")
    private static let cardMuted   = Color(hex: "78716C")
    private static let warmShadow  = Color(hex: "9A6B1A").opacity(0.08)
    private static let cardHair    = Color(hex: "1C1917").opacity(0.05)
    private static let deletePill  = Color(hex: "DC2626")  // red-600
    private static let deleteWash  = Color(hex: "FEE2E2")  // red-100
    private static let freePill    = Color(hex: "D97706")  // amber-600
    private static let freeWash    = Color(hex: "FEF3C7")  // amber-100

    var body: some View {
        ZStack {
            // Shared BitePal canvas — cool blue-lavender → warm
            // light-gray gradient used by every secondary surface.
            LinearGradient(
                stops: [
                    .init(color: Color(hex: "DDE1F2"), location: 0.0),
                    .init(color: Color(hex: "DDE1F2"), location: 0.45),
                    .init(color: Color(hex: "E3E6EE"), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if vm.isDeleting {
                deleteProgressView
            } else {
                VStack(spacing: 0) {
                    reviewTopBar
                    statsHeader

                    if markedItems.isEmpty {
                        emptyState
                    } else {
                        reviewGrid
                    }

                    Spacer()

                    if !markedItems.isEmpty {
                        ActionBar(
                            title: "Delete \(vm.totalMarked) \(vm.mediaLabel) (\(formatBytes(vm.totalBytesMarked)))",
                            buttonTitle: "Delete All",
                            buttonIcon: "trash.fill",
                            isDestructive: true
                        ) {
                            showDeleteConfirm = true
                        }
                    }
                }
            }
        }
        .alert("Delete \(vm.mediaLabel.capitalized)?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete \(vm.totalMarked)", role: .destructive) {
                Task {
                    let success = await vm.deleteMarked()
                    if success {
                        onDeleteComplete()
                    }
                }
            }
        } message: {
            Text("This will permanently delete \(vm.totalMarked) \(vm.mediaLabel) and free up \(formatBytes(vm.totalBytesMarked)).")
        }
        // Warn-haptic on the confirm dialog appearing — the "are you
        // sure?" tactile beat, distinct from the .success that fires
        // after the delete actually lands.
        .onChange(of: showDeleteConfirm) { _, isShown in
            if isShown { HapticManager.shared.notify(.warning) }
        }
    }

    // MARK: - Top Bar
    private var reviewTopBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Self.cardText)
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(Color.white)
                            .shadow(color: Self.warmShadow, radius: 10, y: 4)
                    )
                    .overlay(Circle().stroke(Self.cardHair, lineWidth: 0.5))
            }

            Spacer()

            Text("Review")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(Self.cardText)

            Spacer()

            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Stats Header
    private var statsHeader: some View {
        HStack(spacing: 12) {
            statPill(
                value: "\(vm.totalMarked)",
                label: "To Delete",
                accent: Self.deletePill,
                wash: Self.deleteWash
            )
            statPill(
                value: formatBytes(vm.totalBytesMarked),
                label: "To Free",
                accent: Self.freePill,
                wash: Self.freeWash
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    /// White-card pill with a big espresso value and a soft accent dot
    /// next to the label. Same vocabulary as the Contacts cards.
    private func statPill(value: String, label: String, accent: Color, wash: Color) -> some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundColor(Self.cardText)
                .contentTransition(.numericText())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 6) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Self.cardMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white)
                .shadow(color: Self.warmShadow, radius: 14, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Self.cardHair, lineWidth: 0.5)
        )
        .overlay(alignment: .topLeading) {
            // Tiny accent wash on the corner — a hint of color tying the
            // pill to its data, without flooding the card.
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(wash)
                .frame(width: 60, height: 60)
                .blur(radius: 28)
                .offset(x: -10, y: -10)
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    // MARK: - Review Grid
    private var reviewGrid: some View {
        GeometryReader { geo in
            let cellSize = (geo.size.width - 56) / 3  // 20+20 page pad + 8+8 gutters
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Tap a photo to un-mark it")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(Self.cardMuted)
                    .padding(.horizontal, 20)

                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(markedItems) { item in
                            Button {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    vm.toggleMarkInReview(item.assetId)
                                }
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    PhotoThumbnailView(
                                        assetIdentifier: item.assetId,
                                        size: CGSize(width: cellSize * 2, height: cellSize * 2)
                                    )
                                    .frame(width: cellSize, height: cellSize)
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Self.deletePill.opacity(0.85), lineWidth: 2)
                                    )
                                    .shadow(color: Self.warmShadow, radius: 8, y: 3)

                                    // Crisper white-on-red xmark badge
                                    ZStack {
                                        Circle()
                                            .fill(Self.deletePill)
                                            .frame(width: 22, height: 22)
                                            .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                                        Image(systemName: "xmark")
                                            .font(.system(size: 10, weight: .heavy))
                                            .foregroundColor(.white)
                                    }
                                    .padding(6)
                                }
                            }
                            .buttonStyle(.plain)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 120)
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(hex: "16A34A"))  // green-600

            Text("No \(vm.mediaLabel) marked")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Self.cardText)

            Text("Go back and swipe left on\n\(vm.mediaLabel) you want to delete")
                .font(.system(size: 14))
                .foregroundColor(Self.cardMuted)
                .multilineTextAlignment(.center)

            Spacer()
        }
    }

    // MARK: - Delete Progress
    private var deleteProgressView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView(value: vm.deleteProgress.fraction)
                .progressViewStyle(LinearProgressViewStyle(tint: Self.deletePill))
                .padding(.horizontal, 40)

            VStack(spacing: 6) {
                Text("Deleting \(vm.mediaLabel)…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Self.cardText)

                Text("\(vm.deleteProgress.deleted)/\(vm.deleteProgress.totalToDelete)")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(Self.deletePill)
                    .monospacedDigit()

                if vm.deleteProgress.totalChunks > 1 {
                    Text("Batch \(vm.deleteProgress.currentChunk)/\(vm.deleteProgress.totalChunks)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Self.cardMuted)
                }
            }

            Spacer()
        }
    }
}
