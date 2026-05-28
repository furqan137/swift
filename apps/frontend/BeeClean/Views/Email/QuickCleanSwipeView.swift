import SwiftUI

struct QuickCleanSwipeView: View {
    @ObservedObject var vm: QuickCleanViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showTrashSheet = false

    var body: some View {
        ZStack {
            // Same 3-stop blue-lavender → light-gray gradient as the
            // Email landing page (`EmailCleanerView`) and every email
            // category detail screen — one canvas across the entire
            // email flow, including the swipe deck.
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

            if vm.isLoadingMessages {
                loadingState
            } else if let error = vm.loadError {
                errorState(error)
            } else if vm.messages.isEmpty {
                emptyState
            } else if vm.isComplete {
                completionView
            } else if vm.currentIndex >= vm.messages.count && vm.isLoadingMore {
                // User caught up to loading — show buffer spinner
                VStack(spacing: 20) {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                        .scaleEffect(1.2)
                    Text("Loading more emails...")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.foregroundSecondary)
                    Text("\(vm.messages.count) of \(max(vm.messages.count, vm.category.count)) loaded")
                        .font(.system(size: 13))
                        .foregroundColor(.foregroundSecondary.opacity(0.7))
                    Spacer()
                }
            } else {
                cardStack
                    .padding(.top, 80)
                    .padding(.bottom, 130)
                    .clipped()

                VStack {
                    topBar
                    Spacer()
                    bottomControls
                        .padding(.bottom, 40)
                }
            }
        }
        .sheet(isPresented: $showTrashSheet) {
            QuickCleanTrashSheet(vm: vm)
        }
        .hidesBottomNavBar()
        .task {
            if vm.messages.isEmpty {
                await vm.loadMessages()
            }
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.foreground)
                    .frame(width: 40, height: 40)
                    .background(Color.surfaceLight)
                    .clipShape(Circle())
            }

            Spacer()

            Text("\(vm.currentIndex + 1) / \(max(vm.messages.count, vm.category.count))")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(.foreground)

            Spacer()

            // Trash badge
            Button {
                showTrashSheet = true
            } label: {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.foreground)
                        .frame(width: 40, height: 40)
                        .background(Color.surfaceLight)
                        .clipShape(Circle())

                    if vm.trashCount > 0 {
                        Text("\(vm.trashCount)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.destructive)
                            .clipShape(Capsule())
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .disabled(vm.trashCount == 0)
            .opacity(vm.trashCount == 0 ? 0.4 : 1)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: - Card Stack
    //
    // Renders ONLY the active card. The next card in the queue is kept warm
    // in `vm.messages` (data already in memory) but is never mounted to the
    // view tree while the active card is on screen. After the active card
    // flies off, `vm.currentIndex` advances, `activeCard.id` changes, and
    // SwiftUI hard-cuts in the next card with fresh @State (offset = .zero)
    // — no entry animation.
    private var cardStack: some View {
        GeometryReader { geo in
            let cardWidth = geo.size.width
            let cardHeight = geo.size.height

            ZStack {
                if let active = activeCard {
                    EmailSwipeCard(
                        message: active,
                        cardSize: CGSize(width: cardWidth, height: cardHeight)
                    ) { direction in
                        if direction == .left {
                            vm.swipeLeft()
                        } else {
                            vm.swipeRight()
                        }
                    }
                    .id(active.id)
                    .transition(.identity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 24)
    }

    private var activeCard: EmailMessage? {
        guard vm.currentIndex < vm.messages.count else { return nil }
        return vm.messages[vm.currentIndex]
    }

    // MARK: - Bottom Controls
    //
    // Mirrors the photo `MediaSwipeView.bottomControls` exactly so every
    // swipe deck in the app — Other Photos, Blurry, Screen Recordings,
    // QuickClean email — feels like one consistent control surface.
    // Layout: Undo (50pt) · ✕ Delete (64pt) · ✓ Keep (64pt).
    private var bottomControls: some View {
        HStack(spacing: 32) {
            // Undo
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    vm.undoLast()
                }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.foreground)
                    .frame(width: 50, height: 50)
                    .background(Color.surfaceLight)
                    .clipShape(Circle())
            }
            .disabled(!vm.canUndo)
            .opacity(vm.canUndo ? 1 : 0.3)

            // Delete (swipe left)
            Button {
                vm.swipeLeft()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.destructive)
                    .clipShape(Circle())
            }

            // Keep (swipe right)
            Button {
                vm.swipeRight()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.success)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Completion View
    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.success)

            Text(BCLoc.allDone.tr)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(.foreground)

            if vm.trashCount > 0 {
                Text("\(vm.trashCount) sender\(vm.trashCount == 1 ? "" : "s") in Trash")
                    .font(.system(size: 16))
                    .foregroundColor(.foregroundSecondary)

                PrimaryButton("Review Trash", iconName: "trash.fill") {
                    showTrashSheet = true
                }
                .padding(.horizontal, 40)
            } else {
                Text("No senders were trashed")
                    .font(.system(size: 16))
                    .foregroundColor(.foregroundSecondary)
            }

            SecondaryButton("Close") {
                dismiss()
            }
            .padding(.horizontal, 60)

            Spacer()
        }
    }

    // MARK: - Loading State
    private var loadingState: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .progressViewStyle(CircularProgressViewStyle())
                .scaleEffect(1.2)

            Text("Loading emails in \(vm.category.name)...")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.foregroundSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            SecondaryButton("Cancel") {
                dismiss()
            }
            .padding(.horizontal, 60)

            Spacer()
        }
    }

    // MARK: - Error State
    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundColor(.foregroundSecondary.opacity(0.5))

            Text("Couldn't load emails")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.foreground)

            Text(message)
                .font(.system(size: 14))
                .foregroundColor(.foregroundSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            PrimaryButton("Retry") {
                Task { await vm.loadMessages() }
            }
            .padding(.horizontal, 60)
            .padding(.top, 8)

            SecondaryButton("Close") {
                dismiss()
            }
            .padding(.horizontal, 60)

            Spacer()
        }
    }

    // MARK: - Empty State
    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "tray")
                .font(.system(size: 40))
                .foregroundColor(.foregroundSecondary.opacity(0.5))

            Text("No emails to review")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.foreground)

            Text("This category doesn't have any emails yet.")
                .font(.system(size: 14))
                .foregroundColor(.foregroundSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            SecondaryButton("Close") {
                dismiss()
            }
            .padding(.horizontal, 60)
            .padding(.top, 8)

            Spacer()
        }
    }
}
