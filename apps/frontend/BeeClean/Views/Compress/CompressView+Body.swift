import SwiftUI

// MARK: - CompressView: Body
extension CompressView {

    // MARK: - Body

    var body: some View {
        bodyContent
        // Previously: a 12pt `.blur` on the parent + `.allowsHitTesting(false)`
        // while the filter sheet was up. That combo made the dismiss feel
        // sluggish — SwiftUI animates the blur out, then the hit-testing
        // flips back, then the sheet finishes its slide-down, then the
        // ScrollView's `.task`-bound work resumes. The user perceived this
        // stack of half-seco4nd steps as a 2-second nav-bar lag because the
        // bar (which lives outside this view, in ContentView's outer ZStack)
        // was visually obscured by the sheet during the .medium detent and
        // then "uncovered" only after every step finished. With the sheet
        // now anchored at a 540pt fixed detent (sits above the nav bar) and
        // `.presentationBackgroundInteraction(.enabled(upThrough: .height(540)))`
        // letting the user touch the canvas behind the sheet, the blur +
        // hit-testing block were both fighting that interaction model and
        // adding nothing. Dropped — the sheet's own dimming is enough cue.
        .navigationBarBackButtonHidden(true)
        .overlay { resumeOverlay }
        .onChange(of: category) { _, newCategory in
            // Re-evaluate resume prompt when the user toggles between
            // Photos / Videos so a saved scroll on the other category can
            // surface its own prompt without an app relaunch.
            evaluateResumePrompt(for: newCategory)
        }
        .onChange(of: currentDisplayCount) { _, total in
            // First-time prompt: the very first frame after the grid loads
            // is when we know totalItems. Without this, the .task path
            // below fires when sortedPhotos is still empty and skips the
            // prompt forever.
            guard total > 0 else { return }
            evaluateResumePrompt(for: category)
        }
        // Frost the parent while the filter sheet is open so the
        // top half (visible above the .height(540) detent) reads as
        // a focused-modal context, not just a dimmed pass-through.
        .blur(radius: showFilters ? 8 : 0)
        .animation(.easeOut(duration: 0.2), value: showFilters)
        .sheet(isPresented: $showFilters) {
            // Fixed height (540pt) deliberately chosen to sit ABOVE the
            // floating BottomNavBar — the bar is never visually
            // obscured while the filter is up, so dismissing it feels
            // instant instead of "the nav bar takes 2 seconds to come
            // back". The `.large` second detent is still available so
            // the inline graphical DatePickers (revealed when the user
            // taps Start/End rows) have somewhere to expand into without
            // clipping. Default detent stays 540pt — the user has to
            // explicitly drag up to commit to a full-screen sheet, so
            // the casual filter use case never disturbs the chrome.
            // `presentationBackgroundInteraction(.enabled(upThrough: …))`
            // keeps the underlying view alive to taps even while the
            // sheet is up so the "blocked behind a modal" feel is gone.
            CompressFiltersSheet(
                sortOption: $sortOption,
                startDate: $startDate,
                endDate: $endDate
            )
            .presentationDetents([.height(540), .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
            .presentationBackground(Color.white)
            .presentationBackgroundInteraction(.enabled(upThrough: .height(540)))
        }
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            HapticManager.shared.impact(.light)
            selectedItems = []
            Task { await reloadCurrent() }
        }
        // Refresh the cached sort/filter outputs ONLY when the inputs
        // actually change. The `.task(id:)` modifier diffs on the
        // composite Equatable key — so flipping a sort option, picking
        // a date range, or the underlying scan flushing a new batch
        // re-fires the recompute exactly once instead of on every body
        // invalidation. Body re-renders against unchanged inputs (a
        // scroll, a selection toggle, a sheet open) read the cached
        // arrays as a no-op array indirection.
        .task(id: photoSortKey) {
            recomputeSortedPhotos()
        }
        .task(id: videoSortKey) {
            recomputeSortedVideos()
        }
        .task {
            // Hand off to the singleton-owned scan task. Critically, we
            // do NOT `await` `loadPhotos`/`loadVideos` here: SwiftUI
            // cancels this `.task` whenever the view leaves the screen
            // (tab switch, push onto NavigationStack, etc.), and an
            // awaited scan would be interrupted mid-pass. `ensureLoaded`
            // schedules the work on a Task held by `CompressViewModel`
            // itself, which outlives the view. The view just observes
            // the published state; on re-entry we see whatever progress
            // the singleton has made so far — no flash of empty grid,
            // no full restart.
            vm.ensureLoaded()
        }
    }

    /// Body content extracted out of `body` so SwiftUI's view-builder
    /// can type-check the nested ZStack + conditional branches
    /// independently of the long chain of `.onChange / .task / .sheet`
    /// modifiers below. Without this split, the combined expression
    /// blew past the compiler's reasonable-time budget on the
    /// `BottomNavBar` build target.
    @ViewBuilder
    private var bodyContent: some View {
        ZStack {
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

            mainStack
        }
    }

    @ViewBuilder
    private var mainStack: some View {
        VStack(spacing: 0) {
            header
            categoryPicker

            if currentIsEmpty && !isCurrentLoading {
                Spacer()
                if category == .videos {
                    EmptyVideosView()
                } else {
                    EmptyPhotosView()
                }
                Spacer()
            } else {
                contentScrollView
            }
        }
    }

    @ViewBuilder
    private var contentScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    savingsBanner

                    if hasDateFilter {
                        filterIndicatorInline
                    }

                    if currentDisplayCount == 0 && !isCurrentLoading {
                        noMatchView
                            .padding(.top, 60)
                    } else {
                        contentGrid
                    }
                }
            }
            .onChange(of: resume.promptedCategory) { _, prompted in
                handleResumePromptScroll(prompted: prompted, proxy: proxy)
            }
        }
    }

    private func handleResumePromptScroll(prompted: CompressCategory?, proxy: ScrollViewProxy) {
        guard prompted == nil,
              let savedCategory = pendingScrollCategory else { return }
        let saved = resume.savedIndex(for: savedCategory)
        guard saved > 0, saved < currentDisplayCount else {
            pendingScrollCategory = nil
            return
        }
        let target: String? = {
            if savedCategory == .videos, saved < sortedVideos.count {
                return "v-\(sortedVideos[saved].id)"
            } else if savedCategory == .photos, saved < sortedPhotos.count {
                return "p-\(sortedPhotos[saved].id)"
            }
            return nil
        }()
        if let target {
            withAnimation(.easeInOut(duration: 0.45)) {
                proxy.scrollTo(target, anchor: .top)
            }
        }
        pendingScrollCategory = nil
    }

}

