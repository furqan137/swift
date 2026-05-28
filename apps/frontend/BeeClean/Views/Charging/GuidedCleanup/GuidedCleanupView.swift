import SwiftUI
import Photos

// MARK: - Guided Cleanup View

struct GuidedCleanupView: View {
    @StateObject private var vm: GuidedCleanupViewModel
    @ObservedObject private var progressManager = ProgressManager.shared
    @State private var showShareSheet: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var showReviewSheet = false
    @State private var reviewFilter: GuidedCleanupReviewFilter = .all
    @State private var showNewTaskLauncher = false
    @State private var dragOffset: CGSize = .zero
    @State private var isAnimatingRemoval = false

    init(plan: TodayCleanupPlan, store: SimilarPhotosStore) {
        _vm = StateObject(wrappedValue: GuidedCleanupViewModel(plan: plan, store: store))
    }

    var body: some View {
        ZStack {
            glassBackdrop

            VStack(spacing: 0) {
                topBar
                if !vm.isPoolExhausted && !vm.tasks.isEmpty && !vm.isComplete {
                    checkpointProgressBar
                        .padding(.top, 12)
                }

                if vm.isPoolExhausted {
                    poolExhaustedView
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else if vm.isComplete {
                    completionView
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else if let checkpointIdx = vm.pendingCheckpointTaskIndex {
                    checkpointView(taskIndex: checkpointIdx)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    // Media is the hero: inset slightly from the screen
                    // edges so the rounded card reads as a contained
                    // surface rather than full-bleed.
                    cardStack
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .overlay(alignment: .bottomTrailing) {
                            // TikTok-style action column — anchored to
                            // the lower-right of the card, just above
                            // the storage badge.
                            //
                            // `.id(current.id)` forces SwiftUI to
                            // rebuild the rail's view tree per card so
                            // the heart/bookmark filled state is a
                            // fresh read of SavedFindsStore for THIS
                            // asset, not a stale view-tree carryover
                            // from the previous card.
                            if let current = vm.currentItem {
                                SwipeCardActionRail(
                                    assetId: current.id,
                                    context: railContext(for: current),
                                    onShareRequested: { showShareSheet = true }
                                )
                                .id(current.id)
                                .padding(.trailing, 24)
                                .padding(.bottom, 72)
                            }
                        }
                    Spacer(minLength: 16)
                    actionButtons
                        .padding(.bottom, 24)
                }
            }

        }
        .navigationBarHidden(true)
        .hidesBottomNavBar()
        .sheet(isPresented: $showShareSheet) {
            if let current = vm.currentItem {
                MediaShareSheet(
                    assetId: current.id,
                    onDismiss: { showShareSheet = false }
                )
                .presentationDetents([.height(420)])
                .presentationDragIndicator(.hidden)
            }
        }
        // Catch every exit (back arrow, interactive swipe-back) so coins for
        // finished checkpoints are banked even if the user never hits a CTA.
        // Idempotent — already-credited checkpoints are skipped.
        .onDisappear {
            vm.awardCompletedCheckpoints()
            recordCompletionIfNeeded()
        }
        .fullScreenCover(isPresented: $showReviewSheet) {
            reviewSheet
        }
        .fullScreenCover(isPresented: $showNewTaskLauncher) {
            NewTaskLauncherView(
                onStart: {
                    showNewTaskLauncher = false
                    withAnimation(.easeInOut(duration: 0.3)) {
                        vm.startNewTask()
                    }
                },
                onCancel: {
                    showNewTaskLauncher = false
                }
            )
        }
        .animation(.easeInOut(duration: 0.3), value: vm.isComplete)
        .animation(.easeInOut(duration: 0.3), value: vm.pendingCheckpointTaskIndex)
        .animation(.easeInOut(duration: 0.3), value: vm.isPoolExhausted)
        .onAppear {
            // Take over the audio session — pauses Spotify / YouTube /
            // podcasts so our cleanup video previews play uninterrupted.
            // Released in .onDisappear; reference-counted in the
            // AudioSessionManager so nested swipe flows don't release
            // each other's hold.
            AudioSessionManager.shared.requestExclusivePlayback()
            // #region agent log
            AppDebugLog.write(
                location: "GuidedCleanupView.onAppear",
                message: "guided cleanup session started",
                hypothesisId: "A",
                data: [
                    "tasksCount": vm.tasks.count,
                    "roundGoalBytes": vm.roundGoalBytes,
                    "itemsCount": vm.items.count
                ]
            )
            // #endregion
        }
        .onDisappear {
            AudioSessionManager.shared.releaseExclusivePlayback()
        }
    }

    // MARK: - Pool Exhausted (All Caught Up)

    private var poolExhaustedView: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color(hex: "3A6B3A").opacity(0.12))
                    .frame(width: 100, height: 100)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundColor(Color(hex: "3A6B3A"))
            }

            VStack(spacing: 6) {
                Text("You're all caught up")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text("We'll let you know when there's more to review.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(Color(hex: "3A6B3A"))
                    .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
            }
            .buttonStyle(ScaleButtonStyle())
            .padding(.horizontal, 40)
            .padding(.top, 12)

            Spacer()
        }
    }

    // MARK: - Glass Backdrop
    // Matches Email / Settings / Compress screens.
    private var glassBackdrop: some View {
        LinearGradient(
            stops: [
                .init(color: Color(hex: "DDE1F2"), location: 0.0),
                .init(color: Color(hex: "E3E6EE"), location: 0.45),
                .init(color: Color(hex: "EDEEEF"), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack {
            Button {
                HapticManager.shared.impact(.light)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            }

            Spacer()

            Text("Quick Cleanup")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(.primary)

            Spacer()

            if !vm.isComplete {
                Button {
                    openReviewSheet(filter: .all)
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "trash")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.white)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.06), radius: 4, y: 2)

                        if vm.totalMarked > 0 {
                            Text("\(vm.totalMarked)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Color.red)
                                .clipShape(Capsule())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
            } else {
                Color.clear
                    .frame(width: 36, height: 36)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    // MARK: - Checkpoint Progress Bar (shared yellow tracker)

    private var checkpointProgressBar: some View {
        let filled = vm.completedCheckpointNodes
        let nodeCount = vm.tasks.count + 1
        // #region agent log
        let _ = AppDebugLog.write(
            location: "GuidedCleanupView.checkpointProgressBar",
            message: "progress state",
            hypothesisId: "P1",
            data: [
                "filledNodes": filled,
                "nodeCount": nodeCount,
                "isComplete": vm.isComplete,
                "pendingCheckpoint": vm.pendingCheckpointTaskIndex ?? -1,
                "passedCheckpointCount": vm.passedCheckpointCount,
                "activeTask": vm.activeTaskIndex() ?? -1
            ]
        )
        // #endregion
        return GuidedCleanupCheckpointProgressView(
            tasks: vm.tasks,
            isNodeComplete: { idx in
                filled > 0 && idx <= filled
            },
            isNodeActive: { idx in
                guard !vm.isComplete else { return false }
                if vm.pendingCheckpointTaskIndex != nil { return false }
                if filled == 0 { return idx == 0 }
                let next = filled + 1
                return idx == next && next < nodeCount
            }
        )
    }

    // MARK: - Current Category Pill

    private var currentCategoryPill: some View {
        Group {
            if let item = vm.currentItem {
                let reviewed = vm.reviewedCount(forTask: item.taskIndex)
                let total = vm.totalCount(forTask: item.taskIndex)

                HStack(spacing: 8) {
                    Image(systemName: categoryIcon(for: item.category))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(iconColor(for: item.category))
                    Text(categoryLabel(for: item.category))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("\(reviewed + 1)/\(total)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                    Text(CleanupRound.formatBytes(item.fileSize))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.white)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            }
        }
    }

    // MARK: - Saved-Find Context Mapping

    /// Map a guided-cleanup item to the SavedFindContext the heart /
    /// bookmark rail needs. Picks the matching SavedFindSourceCategory
    /// per CleanupTaskCategory so saves land in the right bucket.
    private func railContext(for item: GuidedItem) -> SavedFindContext {
        let mediaType: SavedFindMediaType = item.category.isVideoCategory ? .video : .photo
        let sourceCategory: SavedFindSourceCategory = {
            switch item.category {
            case .duplicatePhotos:    return .duplicates
            case .similarPhotos:      return .similarPhotos
            case .similarScreenshots: return .similarScreenshots
            case .screenshots:        return .screenshots
            case .blurryPhotos:       return .blurredPhotos
            case .otherPhotos:        return .otherPhotos
            case .similarVideos:      return .similarVideos
            case .screenRecordings:   return .screenRecordings
            case .shortRecordings:    return .shortRecordings
            case .longVideos:         return .longVideos
            case .promoEmails:        return .otherPhotos // unreachable in photo/video flow
            }
        }()
        return SavedFindContext(mediaType: mediaType, sourceCategory: sourceCategory)
    }

    // MARK: - Card Stack

    private var cardStack: some View {
        GeometryReader { geo in
            // Full-bleed: media spans the entire band edge-to-edge. No
            // horizontal padding, no internal cap.
            let w = geo.size.width
            let h = geo.size.height

            if w > 0, h > 0 {
                let size = CGSize(width: w, height: h)
                ZStack {
                    // Active card only. The next 1–2 items are pre-decoded
                    // into AssetThumbnailCache via `prefetchUpcoming` so the
                    // hard-cut to the next card paints synchronously — but
                    // they are NEVER mounted to the view tree while the
                    // active card is on screen. No peek, no offset, no
                    // shadow, no edge visible behind the top card.
                    if let current = vm.currentItem, !isAnimatingRemoval {
                        cardView(item: current, size: size)
                            .offset(dragOffset)
                            .rotationEffect(.degrees(Double(dragOffset.width / 20)))
                            .overlay(swipeOverlay(size: size))
                            .gesture(swipeGesture)
                            .transition(.identity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    prefetchUpcoming(size: size)
                }
                .onChange(of: vm.currentIndex) { _, _ in
                    prefetchUpcoming(size: size)
                }
            }
        }
    }

    /// Decode the next 2 thumbnails into `AssetThumbnailCache` without
    /// mounting them. Matches the size PhotoThumbnailView requests in
    /// `cardView` (the card's own size) so the cache key lines up and the
    /// next card paints on first body eval after the hard cut.
    private func prefetchUpcoming(size: CGSize) {
        let start = vm.currentIndex + 1
        guard start < vm.items.count else { return }
        let end = min(start + 2, vm.items.count)
        let ids = vm.items[start..<end].map { $0.id }
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        var assets: [PHAsset] = []
        fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
        AssetThumbnailCache.shared.prefetch(assets, size: size, limit: 2)
    }

    private func cardView(item: GuidedItem, size: CGSize) -> some View {
        ZStack(alignment: .top) {
            // Cover-fit: media fills the full band, cropping as needed.
            // SwipeCardMedia auto-detects video vs photo — videos mount an
            // AVPlayerLooper-backed AutoPlayingVideoCard (muted, looped, no
            // controls), photos render via PhotoThumbnailView. Because the
            // parent `cardStack` keys the active card on `vm.currentItem`,
            // a fresh SwipeCardMedia is constructed every swipe, so the
            // new asset's player kicks off the moment it appears.
            SwipeCardMedia(
                assetId: item.id,
                cardSize: size
            )
            .frame(width: size.width, height: size.height)
            .clipped()

            // Floating pills — moved to the TOP of the card so the
            // bottom edge is clear for the TikTok-style action rail and
            // its share-sheet readability.
            HStack {
                Text(categoryLabel(for: item.category))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())

                Spacer()

                Text(CleanupRound.formatBytes(item.fileSize))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)

            // Best shot badge — moved to BOTTOM-left now that the
            // category / size pills migrated to the top edge. Keeps the
            // top row clean (just two pills) and gives the badge its
            // own corner so it doesn't crowd them.
            if item.isBest {
                VStack {
                    Spacer()
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                            Text("Best Shot")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(Color(hex: "996515"))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(hex: "FFD700").opacity(0.85))
                        .clipShape(Capsule())
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                        Spacer()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func swipeOverlay(size: CGSize) -> some View {
        ZStack {
            // DELETE overlay (swiping left)
            if dragOffset.width < 0 {
                Text("DELETE")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.red)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.red, lineWidth: 3)
                    )
                    .rotationEffect(.degrees(12))
                    .opacity(Double(min(abs(dragOffset.width) / 100, 1.0)))
                    .offset(x: 30, y: -20)
            }

            // KEEP overlay (swiping right)
            if dragOffset.width > 0 {
                Text("KEEP")
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(Color(hex: "3A6B3A"))
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "3A6B3A"), lineWidth: 3)
                    )
                    .rotationEffect(.degrees(-12))
                    .opacity(Double(min(abs(dragOffset.width) / 100, 1.0)))
                    .offset(x: -30, y: -20)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                let threshold: CGFloat = 100
                if value.translation.width < -threshold {
                    // Swipe left → delete
                    withAnimation(.easeOut(duration: 0.25)) {
                        dragOffset = CGSize(width: -500, height: value.translation.height)
                    }
                    isAnimatingRemoval = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        dragOffset = .zero
                        vm.swipeLeft()
                        isAnimatingRemoval = false
                    }
                } else if value.translation.width > threshold {
                    // Swipe right → keep
                    withAnimation(.easeOut(duration: 0.25)) {
                        dragOffset = CGSize(width: 500, height: value.translation.height)
                    }
                    isAnimatingRemoval = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        dragOffset = .zero
                        vm.swipeRight()
                        isAnimatingRemoval = false
                    }
                } else {
                    // Snap back
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        dragOffset = .zero
                    }
                }
            }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 28) {
            // Delete
            Button {
                triggerSwipeLeft()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.red)
                    .clipShape(Circle())
                    .shadow(color: Color.red.opacity(0.3), radius: 8, y: 4)
            }
            .disabled(vm.currentItem == nil)
            .buttonStyle(ScaleButtonStyle())

            // Undo
            Button {
                vm.undoLast()
                HapticManager.shared.impact(.light)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(vm.canUndo ? .primary : Color(hex: "C7C7CC"))
                    .frame(width: 44, height: 44)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
            }
            .disabled(!vm.canUndo)
            .buttonStyle(ScaleButtonStyle())

            // Keep
            Button {
                triggerSwipeRight()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 64, height: 64)
                    .background(Color(hex: "3A6B3A"))
                    .clipShape(Circle())
                    .shadow(color: Color(hex: "3A6B3A").opacity(0.3), radius: 8, y: 4)
            }
            .disabled(vm.currentItem == nil)
            .buttonStyle(ScaleButtonStyle())
        }
    }

    private func triggerSwipeLeft() {
        withAnimation(.easeOut(duration: 0.25)) {
            dragOffset = CGSize(width: -500, height: 0)
        }
        isAnimatingRemoval = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dragOffset = .zero
            vm.swipeLeft()
            isAnimatingRemoval = false
        }
    }

    private func triggerSwipeRight() {
        withAnimation(.easeOut(duration: 0.25)) {
            dragOffset = CGSize(width: 500, height: 0)
        }
        isAnimatingRemoval = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            dragOffset = .zero
            vm.swipeRight()
            isAnimatingRemoval = false
        }
    }

    // MARK: - Checkpoint View

    private func checkpointView(taskIndex: Int) -> some View {
        GuidedCleanupCelebrationView(
            content: vm.checkpointCelebration(for: taskIndex),
            onPrimary: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    vm.continueAfterCheckpoint()
                }
            }
        )
    }

    // MARK: - Shuffling System completion

    /// Record the finished session to the persistent cleanup history and rotate
    /// the active task forward — exactly once per session (guarded in the VM).
    /// Fires from the completion screen, the back arrow, and onDisappear so any
    /// exit with real work done is captured.
    private func recordCompletionIfNeeded() {
        guard vm.isComplete || vm.totalCoinsEarned > 0 else { return }
        guard vm.markCompletionRecorded() else { return }
        let result = CompletedTaskResult(
            taskTitle: "Quick Cleanup",
            taskType: "quick_cleanup",
            category: (vm.dominantSessionCategory ?? .otherPhotos).rawValue,
            mbReviewed: Double(vm.sessionBytesCleaned) / 1_000_000,
            coinsEarned: vm.totalCoinsEarned,
            levelAtCompletion: ProgressManager.shared.currentLevel,
            assetCount: vm.sessionDeletedCount
        )
        Task { await CleanupTaskManager.shared.completeActiveTask(result: result) }
    }

    // MARK: - Completion View (Task Summary)

    private var completionView: some View {
        GuidedCleanupCompletionView(
            vm: vm,
            onBackToDashboard: { finishAndReturnToDashboard() },
            onPhotoCardTap: { openReviewSheet(filter: .photos) },
            onVideoCardTap: { openReviewSheet(filter: .videos) },
            isPrimaryDisabled: vm.isDeleting || vm.completionDeletionPhase != .idle
        )
    }

    private func openReviewSheet(filter: GuidedCleanupReviewFilter) {
        reviewFilter = filter
        // #region agent log
        AppDebugLog.write(
            location: "GuidedCleanupView.openReviewSheet",
            message: "review sheet requested",
            hypothesisId: "H3",
            data: [
                "filter": String(describing: filter),
                "isComplete": vm.isComplete,
                "totalMarked": vm.totalMarked,
                "photoCount": vm.markedPhotoCount,
                "videoCount": vm.markedVideoCount
            ]
        )
        // #endregion
        showReviewSheet = true
    }

    /// Shows iOS delete dialog first; in-place completion animations after confirm.
    private func finishAndReturnToDashboard() {
        guard vm.completionDeletionPhase == .idle, !vm.isDeleting else { return }
        if vm.totalMarked == 0 {
            vm.clearSessionState()
            dismiss()
            return
        }
        runCompletionDeletion(filter: .all)
    }

    private func runCompletionDeletion(filter: GuidedCleanupReviewFilter) {
        guard vm.completionDeletionPhase == .idle else { return }
        showReviewSheet = false

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)

            vm.onPhotoLibraryDeleteConfirmed = {
                vm.beginDeletionStatusMessages(for: filter)
                // #region agent log
                AppDebugLog.write(
                    location: "GuidedCleanupView.onPhotoLibraryDeleteConfirmed",
                    message: "PhotoKit confirmed, in-place animations started",
                    hypothesisId: "H5",
                    data: ["filter": String(describing: filter)]
                )
                // #endregion
            }

            // #region agent log
            AppDebugLog.write(
                location: "GuidedCleanupView.runCompletionDeletion",
                message: "awaiting PhotoKit delete dialog",
                hypothesisId: "H5",
                data: ["filter": String(describing: filter)]
            )
            // #endregion

            let success = await deleteForFilter(filter)
            vm.onPhotoLibraryDeleteConfirmed = nil

            if success {
                vm.showCompletionDeletionSuccess()
                HapticManager.shared.notify(.success)
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                vm.clearSessionState()
                dismiss()
            } else {
                vm.resetCompletionDeletionUI()
            }
        }
    }

    private func deleteForFilter(_ filter: GuidedCleanupReviewFilter) async -> Bool {
        switch filter {
        case .all:
            return await vm.deleteAllMarked()
        case .photos:
            return await vm.deleteMarked { $0.category.isPhotoCategory }
        case .videos:
            return await vm.deleteMarked { $0.category.isVideoCategory }
        }
    }

    // MARK: - Review Sheet

    private var reviewSheet: some View {
        NavigationView {
            ZStack {
                glassBackdrop

                if filteredMarkedItems.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trash.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("No items to delete")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                } else {
                    VStack(spacing: 0) {
                        // Summary header
                        HStack {
                            Text("\(filteredMarkedItems.count) item\(filteredMarkedItems.count == 1 ? "" : "s")")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(CleanupRound.formatBytes(filteredBytesMarked))
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "3A6B3A"))
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)

                        ScrollView {
                            let columns = [
                                GridItem(.flexible(), spacing: 3),
                                GridItem(.flexible(), spacing: 3),
                                GridItem(.flexible(), spacing: 3)
                            ]

                            LazyVGrid(columns: columns, spacing: 3) {
                                ForEach(filteredMarkedItems) { item in
                                    Button {
                                        vm.unmarkItem(item.id)
                                    } label: {
                                        ZStack(alignment: .topTrailing) {
                                            PhotoThumbnailView(
                                                assetIdentifier: item.id,
                                                size: CGSize(width: 130, height: 130),
                                                contentMode: .fill
                                            )
                                            .frame(height: 130)
                                            .clipped()

                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 20))
                                                .foregroundColor(.white)
                                                .shadow(radius: 2)
                                                .padding(6)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 3)
                        }

                        // Delete All button
                        Button {
                            runCompletionDeletion(filter: reviewFilter)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "trash.fill")
                                Text("Delete All (\(filteredMarkedItems.count))")
                            }
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.red)
                            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.lg, style: .continuous))
                        }
                        .disabled(vm.completionDeletionPhase != .idle)
                        .buttonStyle(ScaleButtonStyle())
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                    }
                }
            }
            .navigationTitle(reviewSheetTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        showReviewSheet = false
                    }
                    .font(.system(size: 16, weight: .semibold))
                }
            }
        }
    }

    private var markedItems: [GuidedItem] {
        vm.items.filter { vm.markedForDeletion.contains($0.id) }
    }

    private var filteredMarkedItems: [GuidedItem] {
        switch reviewFilter {
        case .all:
            return markedItems
        case .photos:
            return markedItems.filter { $0.category.isPhotoCategory }
        case .videos:
            return markedItems.filter { $0.category.isVideoCategory }
        }
    }

    private var filteredBytesMarked: Int64 {
        filteredMarkedItems.reduce(Int64(0)) { $0 + $1.fileSize }
    }

    private var reviewSheetTitle: String {
        switch reviewFilter {
        case .all: return "Review Deletions"
        case .photos: return "Photos to Delete"
        case .videos: return "Videos to Delete"
        }
    }

    // MARK: - Helpers

    private func iconColor(for category: CleanupTaskCategory) -> Color {
        switch category {
        case .duplicatePhotos: return .categorySky
        case .similarPhotos: return .categoryViolet
        case .similarScreenshots: return .categoryTeal
        case .screenshots: return .categoryAmber
        case .blurryPhotos: return .categoryRose
        case .similarVideos: return .categoryCrimson
        case .screenRecordings: return .categoryIndigo
        case .shortRecordings: return .categoryMint
        case .longVideos: return .categoryCocoa
        case .otherPhotos: return .categorySlate
        case .promoEmails: return .categorySlate
        }
    }

    private func categoryIcon(for category: CleanupTaskCategory) -> String {
        switch category {
        case .duplicatePhotos: return "doc.on.doc.fill"
        case .similarPhotos: return "photo.on.rectangle"
        case .similarScreenshots: return "rectangle.on.rectangle"
        case .screenshots: return "rectangle.on.rectangle"
        case .blurryPhotos: return "camera.metering.unknown"
        case .similarVideos: return "film.fill"
        case .screenRecordings: return "record.circle"
        case .shortRecordings: return "video.fill"
        case .longVideos: return "film.fill"
        case .otherPhotos: return "photo.fill"
        case .promoEmails: return "envelope.fill"
        }
    }

    private func categoryLabel(for category: CleanupTaskCategory) -> String {
        switch category {
        case .duplicatePhotos: return "Duplicate"
        case .similarPhotos: return "Similar"
        case .similarScreenshots: return "Screenshot"
        case .screenshots: return "Screenshot"
        case .blurryPhotos: return "Blurry"
        case .similarVideos: return "Video"
        case .screenRecordings: return "Screen Rec"
        case .shortRecordings: return "Short Video"
        case .longVideos: return "Large Video"
        case .otherPhotos: return "Photo"
        case .promoEmails: return "Email"
        }
    }
}
