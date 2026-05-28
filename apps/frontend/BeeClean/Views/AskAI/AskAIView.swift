import SwiftUI

// MARK: - Ask AI View
struct AskAIView: View {
    @ObservedObject private var aiService = AIService.shared
    @ObservedObject private var indexingService = IndexingService.shared
    @ObservedObject private var authService = AuthService.shared
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var selectedAction: AIAction?
    @State private var showResults = false
    @State private var isAtBottom = true

    /// Guards lifecycle logic in `onAppear` so it only runs on the very
    /// first appearance — not when returning from a navigation destination
    /// (e.g. AIResultsGridView).
    @State private var hasAppearedOnce = false

    // Sidebar state — single source of truth
    @State private var showSideMenu = false
    @State private var sidebarDragOffset: CGFloat = 0
    /// One-shot guard so the sidebar-drag commitment-threshold haptic
    /// fires once per drag, not on every onChanged tick after the
    /// threshold is crossed. Reset on `.onEnded`.
    @State private var didHitSidebarThreshold = false
    /// One-shot guard for the "first character typed" haptic. Fires
    /// once per message cycle when the input transitions empty →
    /// has-content; resets on Send so the next message gets its own
    /// fresh first-key cue.
    @State private var hasTypedFirstKey = false

    @AppStorage("userName") private var beeName = ""
    @Environment(\.dismiss) private var dismiss
    /// Scene phase, watched so we can flush ChatHistoryService's
    /// debounced server uploads the instant the app goes inactive.
    /// Without this, a type-then-quit user's freshest 800ms of edits
    /// stay parked in UserDefaults and only reach the server next
    /// launch — fine for single-device but produces a cross-device
    /// sync gap when the user opens the app elsewhere first.
    @Environment(\.scenePhase) private var scenePhase

    private var sidebarWidth: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 393
    }

    private var displayBeeName: String {
        let trimmed = beeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "BeeBuddy" : trimmed
    }

    /// Whether Ask Bee needs the setup/progress screen. The chat is only
    /// accessible once indexing is fully complete — until then, the user
    /// sees IndexingProgressView which handles every non-complete state
    /// (permission prompts, progress bar, paused, failed, etc.).
    private var needsSetup: Bool {
        indexingService.state != .complete
    }

    /// Current pixel offset of the main content (0 = closed, -sidebarWidth = open).
    private var effectiveOffset: CGFloat {
        let base: CGFloat = showSideMenu ? -sidebarWidth : 0
        return max(min(base + sidebarDragOffset, 0), -sidebarWidth)
    }

    /// Normalised sidebar progress (0 = fully closed, 1 = fully open).
    private var sidebarProgress: CGFloat {
        abs(effectiveOffset) / sidebarWidth
    }

    // MARK: - Body

    var body: some View {
        Group {
            if !authService.isAuthenticated {
                // Gate 1: Gmail account required (same auth as Email tab)
                EmailSignInPrompt(onSuccess: {
                    indexingService.startIfNeeded()
                })
            } else if needsSetup {
                // Gate 2: Indexing must complete before chat is usable
                setupView
            } else {
                chatView
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $showResults) {
            if let action = selectedAction {
                AIResultsGridView(action: action)
            }
        }
    }

    // MARK: - Chat View (normal state)

    private var chatView: some View {
        ZStack(alignment: .trailing) {
            SideMenuView(
                isOpen: showSideMenu,
                onClose: { closeSidebar() },
                onNewChat: {
                    startNewChat()
                    closeSidebar()
                },
                onSelectHistory: { session in
                    ChatHistoryService.shared.currentSessionId = session.id
                    withAnimation(.easeInOut(duration: 0.25)) {
                        aiService.loadMessages(session.messages)
                    }
                    closeSidebar()
                }
            )
            .frame(width: sidebarWidth)

            ZStack {
                mainContent

                Color.black
                    .opacity(0.35 * sidebarProgress)
                    .ignoresSafeArea()
                    .allowsHitTesting(sidebarProgress > 0.01)
                    .onTapGesture { closeSidebar() }
            }
            .offset(x: effectiveOffset)
        }
        .simultaneousGesture(sidebarDragGesture)
        .onChange(of: isInputFocused) { _, newValue in
            // Whisper "I'm listening" the moment the keyboard rises.
            // Only fires on focus gain — losing focus (keyboard
            // dismiss) shouldn't tick.
            if newValue {
                HapticManager.shared.inputFieldFocus()
            }
        }
        .onChange(of: inputText) { oldValue, newValue in
            // One-shot first-key tick on the empty → has-content
            // transition. `hasTypedFirstKey` resets in `sendMessage()`
            // so the next message gets its own cue. Trimmed so a
            // stray space doesn't fire it.
            let oldTrimmed = oldValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let newTrimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if oldTrimmed.isEmpty && !newTrimmed.isEmpty && !hasTypedFirstKey {
                hasTypedFirstKey = true
                HapticManager.shared.typingFirstKey()
            } else if newTrimmed.isEmpty {
                // Field emptied (backspace to nothing, send clear) —
                // re-arm the first-key guard so the next typed character
                // fires again.
                hasTypedFirstKey = false
            }
        }
        .onAppear {
            // Lifecycle / restore logic must only run on the FIRST
            // appearance — not when returning from a pushed navigation
            // destination (e.g. AIResultsGridView). Without this guard,
            // `shouldStartFreshOnLaunch` (a `let` constant that stays
            // true for the whole process) would clear the chat every
            // time the user pops back from the results grid.
            if !hasAppearedOnce {
                hasAppearedOnce = true

                let lifecycle = AppLifecycleManager.shared
                if lifecycle.shouldStartFreshOnLaunch {
                    // Cold start after force-quit or long absence — don't restore.
                    // If there's an existing chat in memory (shouldn't happen on
                    // cold start, but guard anyway), save it first.
                    if aiService.messages.count > 1 {
                        ChatHistoryService.shared.syncCurrent(messages: aiService.messages)
                        ChatHistoryService.shared.startNewChat()
                        aiService.clearChat()
                    }
                } else if aiService.messages.count <= 1,
                          let lastSession = ChatHistoryService.shared.sessions.first {
                    // Short absence — restore last session (existing behavior)
                    aiService.loadMessages(lastSession.messages)
                    ChatHistoryService.shared.currentSessionId = lastSession.id
                }
            }
            // Kick off indexing if it hasn't started yet so CLIP embeddings
            // build in the background while the user chats.
            indexingService.startIfNeeded()
        }
        .onDisappear {
            ChatHistoryService.shared.syncCurrent(messages: aiService.messages)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
        ) { _ in
            // Warm resume: app stayed alive but was backgrounded >30 min
            guard AppLifecycleManager.shared.hasBeenInactiveForTooLong() else { return }
            guard aiService.messages.count > 1 else { return }
            ChatHistoryService.shared.syncCurrent(messages: aiService.messages)
            ChatHistoryService.shared.startNewChat()
            withAnimation(.easeInOut(duration: 0.25)) {
                aiService.clearChat()
                inputText = ""
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // App heading to background or about to be terminated.
            // Two-step push: first flush the live in-memory chat into
            // the store (so the latest user keystroke is captured),
            // then drop the 800ms debounce and shove every pending
            // upload to the server. Single-device users are unaffected
            // (UserDefaults `save()` already wrote synchronously);
            // this closes the cross-device gap where a quick
            // type-then-quit leaves the latest edits parked locally
            // until next launch.
            guard phase == .inactive || phase == .background else { return }
            if aiService.messages.contains(where: { $0.role == .user }) {
                ChatHistoryService.shared.syncCurrent(messages: aiService.messages)
            }
            ChatHistoryService.shared.flushPendingUploads()
        }
    }

    // MARK: - Setup View

    private var setupView: some View {
        ZStack {
            BitepalCanvas()

            VStack(spacing: 0) {
                // Simple back button
                HStack {
                    Button {
                        HapticManager.shared.arrowNudge(.backward)
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "1C1917"))
                            .frame(width: 38, height: 38)
                            .background(
                                Circle()
                                    .fill(Color(hex: "F5F5F4"))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                                    )
                            )
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                Spacer()

                VStack(spacing: 24) {
                    AppIconAvatar(size: 100)

                    VStack(spacing: 8) {
                        switch indexingService.state {
                        case .blockedNoPhotoPermission:
                            Text("Enable Photo Access")
                                .font(.custom("Poppins-Bold", size: 22))
                                .foregroundColor(.foreground)
                            Text("Ask Bee needs access to your photos to help you search and organize them.")
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.mutedForeground)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        default:
                            Text("Preparing Ask Bee")
                                .font(.custom("Poppins-Bold", size: 22))
                                .foregroundColor(.foreground)
                            Text("Bee is learning your photo library so you can search by describing what you're looking for.")
                                .font(.custom("Poppins-Regular", size: 14))
                                .foregroundColor(.mutedForeground)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                        }
                    }

                    switch indexingService.state {
                    case .inProgress(_, let progress):
                        VStack(spacing: 12) {
                            if progress > 0 {
                                ProgressView(value: progress)
                                    .tint(Color(hex: "1C1917"))
                                    .padding(.horizontal, 48)
                            } else {
                                ProgressView()
                                    .tint(Color(hex: "1C1917"))
                            }
                            Text(indexingService.statusLine)
                                .font(.labelMedium)
                                .foregroundColor(.mutedForeground)
                        }

                    case .paused:
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(Color(hex: "1C1917"))
                            Text(indexingService.statusLine)
                                .font(.labelMedium)
                                .foregroundColor(.mutedForeground)
                        }

                    case .failed(let error):
                        VStack(spacing: 16) {
                            Text(error)
                                .font(.bodySmall)
                                .foregroundColor(.mutedForeground)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)

                            Button {
                                HapticManager.shared.impact(.medium, intensity: 0.7)
                                // Retry by restarting the indexing service
                                indexingService.startIfNeeded()
                            } label: {
                                Text(BCLoc.retry.tr)
                                    .font(.custom("Poppins-SemiBold", size: 16))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(hex: "1C1917"))
                                    )
                            }
                            .padding(.horizontal, 48)
                        }

                    case .notStarted:
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(Color(hex: "1C1917"))
                            Text("Preparing your library...")
                                .font(.labelMedium)
                                .foregroundColor(.mutedForeground)
                        }

                    case .blockedNoPhotoPermission:
                        let photoKitStatus = PhotoKitService.shared.authorizationStatus
                        if photoKitStatus == .denied || photoKitStatus == .restricted {
                            VStack(spacing: 12) {
                                Text("Photo access was denied. You can enable it in Settings.")
                                    .font(.bodySmall)
                                    .foregroundColor(.mutedForeground)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 32)

                                Button {
                                    if let url = URL(string: UIApplication.openSettingsURLString) {
                                        UIApplication.shared.open(url)
                                    }
                                } label: {
                                    Text(BCLoc.openSettings.tr)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                        .background(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .fill(Color(hex: "1C1917"))
                                        )
                                }
                                .padding(.horizontal, 48)
                            }
                        } else {
                            Button {
                                Task {
                                    await PhotoKitService.shared.requestAuthorization()
                                }
                            } label: {
                                Text("Allow Photo Access")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(Color(hex: "1C1917"))
                                    )
                            }
                            .padding(.horizontal, 48)
                        }

                    case .complete:
                        EmptyView() // Should not reach here; needsSetup is false
                    }
                }

                Spacer()
                Spacer()
            }
        }
        .onAppear {
            PhotoKitService.shared.checkAuthorizationStatus()
            // Trigger indexing for existing authenticated users who need a fresh index
            // (e.g., after app update that bumped pipelineVersion)
            indexingService.startIfNeeded()
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ZStack(alignment: .top) {
            // Chat background — `BitepalCanvas` cool-gray gradient
            // (#DDE1F2 → #E3E6EE → #EDEEEF). All floating elements
            // (header pills, AI bubbles, input pill) are solid
            // `Color.white` — same token as the Compress storage card —
            // so the contrast against the gradient is consistent
            // across screens.
            BitepalCanvas()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        // Transparent leading spacer sized to the frosted
                        // header's full height (status bar + pill stack).
                        Color.clear.frame(height: FrostedChatHeaderMetrics.totalHeight(safeAreaTop: safeAreaTop))

                        // Messages with timestamp separators
                        LazyVStack(spacing: 2) {
                            ForEach(Array(aiService.messages.enumerated()), id: \.element.id) { index, message in
                                MessageBubbleView(
                                    message: message,
                                    showTail: isLastInGroup(at: index),
                                    onGridTap: message.assetIds != nil && !(message.assetIds?.isEmpty ?? true) ? {
                                        if let action = message.actions.first {
                                            selectedAction = action
                                            showResults = true
                                        }
                                    } : nil,
                                    onRetry: message.state.isFailed ? {
                                        if let action = message.actions.first {
                                            Task {
                                                do {
                                                    let ids = try await AIService.shared.executeAction(action)
                                                    AIService.shared.updateMessage(id: message.id) { msg in
                                                        msg.assetIds = ids
                                                        msg.state = .complete
                                                    }
                                                    HapticManager.shared.impact(.medium, intensity: 0.7)
                                                } catch {
                                                    let errorMsg: String
                                                    if let searchErr = error as? AISearchError {
                                                        errorMsg = searchErr.localizedDescription
                                                    } else {
                                                        errorMsg = "Something went wrong: \(error.localizedDescription)"
                                                    }
                                                    AIService.shared.updateMessage(id: message.id) { msg in
                                                        msg.state = .failed(errorMsg)
                                                    }
                                                    // Soft warning tick as the red error
                                                    // bubble lands — pairs with the visual
                                                    // so the failure has a felt presence
                                                    // even when the user isn't watching.
                                                    HapticManager.shared.notify(.warning)
                                                }
                                            }
                                        }
                                    } : nil
                                )
                                .id(message.id)
                                .padding(.top, spacingBefore(at: index))
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .opacity
                                ))
                            }

                            if aiService.isLoading {
                                TypingIndicatorView()
                                    .id("typing")
                                    .padding(.top, 6)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)

                        // Bottom anchor for scroll detection
                        Color.clear.frame(height: 1).id("bottom")
                            .onAppear { isAtBottom = true }
                            .onDisappear { isAtBottom = false }
                    } // VStack(spacing: 0)
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.top, 0)
                    .scrollDismissesKeyboard(.interactively)
                    .onTapGesture { isInputFocused = false }
                    .onChange(of: aiService.messages.count) {
                        ChatHistoryService.shared.syncCurrent(messages: aiService.messages)
                        withAnimation {
                            if aiService.isLoading {
                                proxy.scrollTo("typing", anchor: .bottom)
                            } else if let lastId = aiService.messages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: aiService.isLoading) {
                        withAnimation {
                            if aiService.isLoading {
                                proxy.scrollTo("typing", anchor: .bottom)
                            } else if let lastId = aiService.messages.last?.id {
                                proxy.scrollTo(lastId, anchor: .bottom)
                            }
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if !isAtBottom && !aiService.messages.isEmpty {
                            Button {
                                HapticManager.shared.buttonTap()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    proxy.scrollTo("bottom", anchor: .bottom)
                                }
                            } label: {
                                Image(systemName: "arrow.down")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Circle().fill(Color.black))
                                    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
                            }
                            .padding(.bottom, 8)
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    // Input row attached via `.safeAreaInset` so the
                    // ScrollView extends all the way to the bottom of
                    // the screen. That way the chat background is the
                    // same layer below the pill as it is behind the
                    // scroll content — no separate "white tray" under
                    // the input bar — and bubbles scroll cleanly under
                    // the pill as the user moves them up.
                    //
                    // CRITICAL: no `.background(...)` on this inset
                    // view, and no background on `ChatInputBar` or the
                    // wrapping VStack. A background here would recreate
                    // the grey tray we removed. Keyboard avoidance and
                    // bottom safe-area clearance are handled by the
                    // system; do not add manual padding here.
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        VStack(spacing: 0) {
                            ChatInputBar(
                                text: $inputText,
                                isLoading: aiService.isLoading,
                                isFocused: $isInputFocused,
                                onSend: { sendMessage(inputText) }
                            )
                        }
                        // Opaque mask that blocks scroll content from
                        // bleeding past the input bar into the
                        // home-indicator zone (rubber-band, fast
                        // flicks). Color is the BOTTOM stop of
                        // `BitepalCanvas` (`#EDEEEF`) — matching the
                        // gradient's final color where this inset
                        // physically sits, so the mask blends into the
                        // page seamlessly instead of reading as a
                        // separate tray. Do NOT change this to a solid
                        // mid/top gradient color — they're darker than
                        // the bottom of the gradient and would reveal
                        // this inset as a distinct tray.
                        .background(Color(hex: "EDEEEF"))
                    }
            }

            // Chat header — three solid-white pills (back+unread /
            // avatar+name / menu). Chat content scrolls under the pills
            // and through the transparent gaps between them.
            FrostedChatHeader(
                contactName: displayBeeName,
                // The AI chat doesn't track unread message counts, so the
                // badge stays hidden; the prop is kept for parity with
                // the spec'd component API and future contact-style use.
                unreadCount: 0,
                onBack: {
                    ChatHistoryService.shared.syncCurrent(messages: aiService.messages)
                    dismiss()
                },
                onContactTap: { openSidebar() },
                trailingIcon: "line.3.horizontal",
                trailingAction: { openSidebar() },
                avatar: { AppIconAvatar(size: 60) }
            )
            .ignoresSafeArea(edges: .top)
            .zIndex(1)
        }
    }

    private var safeAreaTop: CGFloat {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first?.safeAreaInsets.top ?? 44
    }


    private func isLastInGroup(at index: Int) -> Bool {
        // Bounds-guard the whole range. `ForEach(Array(messages.enumerated()))`
        // can briefly hand us stale indices during `aiService.messages`
        // mutation (new reply arrives, a chat-history swap replaces the
        // array, etc.), and an out-of-range read here crashed TestFlight.
        // Returning `true` (i.e. "treat as end of group") is the visually
        // safe fallback — it just means the bubble gets a tail.
        let messages = aiService.messages
        guard index >= 0, index < messages.count else { return true }
        if index == messages.count - 1 { return true }
        return messages[index].role != messages[index + 1].role
    }

    private func spacingBefore(at index: Int) -> CGFloat {
        // Same rationale as isLastInGroup — guard both ends before indexing.
        let messages = aiService.messages
        guard index > 0, index < messages.count else { return 0 }
        // Different sender → more space
        if messages[index].role != messages[index - 1].role { return 6 }
        return 2
    }

    // MARK: - Sidebar Drag Gesture
    //
    // Sidebar sits on the RIGHT. Content slides LEFT to reveal it.
    //
    // When sidebar is CLOSED:
    //   Swipe LEFT from anywhere → open sidebar
    // When sidebar is OPEN:
    //   Swipe RIGHT anywhere → close sidebar
    //   Tap dim area          → close sidebar

    private var sidebarDragGesture: some Gesture {
        DragGesture(minimumDistance: 15, coordinateSpace: .global)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                // Don't steal swipe-right gestures starting near the left edge —
                // let the native navigation pop gesture handle those.
                if !showSideMenu && value.startLocation.x < 30 && value.translation.width > 0 {
                    return
                }

                if showSideMenu {
                    // Sidebar open — swipe right to close
                    sidebarDragOffset = max(0, value.translation.width)
                } else if value.translation.width < 0 {
                    // Swipe left from anywhere → open sidebar
                    sidebarDragOffset = min(0, value.translation.width)
                }

                // Once the drag passes the commitment threshold (same
                // 30% the onEnded uses to decide "open"), fire a single
                // tick so the user feels the moment the gesture has
                // crossed into "yes, this will open the sidebar."
                // `didHitSidebarThreshold` guards re-firing while the
                // user keeps dragging past the threshold; it resets on
                // .onEnded.
                if !didHitSidebarThreshold
                    && !showSideMenu
                    && abs(sidebarDragOffset) > sidebarWidth * 0.3 {
                    didHitSidebarThreshold = true
                    HapticManager.shared.selection()
                }
            }
            .onEnded { value in
                let velocity = value.predictedEndTranslation.width
                // Re-arm the threshold guard for the next drag.
                didHitSidebarThreshold = false

                if showSideMenu {
                    // Close if swiped far enough right or flicked right
                    if abs(effectiveOffset) < sidebarWidth * 0.5 || velocity > 500 {
                        closeSidebar()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            sidebarDragOffset = 0
                        }
                    }
                } else if value.translation.width < 0 {
                    // Open sidebar if swiped far enough left or flicked left
                    if abs(effectiveOffset) > sidebarWidth * 0.3 || velocity < -500 {
                        openSidebar()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            sidebarDragOffset = 0
                        }
                    }
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        sidebarDragOffset = 0
                    }
                }
            }
    }

    // MARK: - Sidebar Helpers

    private func openSidebar() {
        HapticManager.shared.impact(.light, intensity: 0.5)
        ChatHistoryService.shared.syncCurrent(messages: aiService.messages)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showSideMenu = true
            sidebarDragOffset = 0
        }
    }

    private func closeSidebar() {
        HapticManager.shared.impact(.light, intensity: 0.4)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            showSideMenu = false
            sidebarDragOffset = 0
        }
    }

    // MARK: - New Chat

    private func startNewChat() {
        // Same primary-commit feel as the side-menu "New Chat" row —
        // committing to a fresh chat is heavier than the light rotor
        // ticks used for filter/scope changes.
        HapticManager.shared.primaryCommit()
        ChatHistoryService.shared.syncCurrent(messages: aiService.messages)
        ChatHistoryService.shared.startNewChat()
        withAnimation(.easeInOut(duration: 0.25)) {
            aiService.clearChat()
            inputText = ""
        }
    }

    // MARK: - Send Message

    private func sendMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        inputText = ""

        // Track first query ever sent
        if !UserDefaults.standard.bool(forKey: "ask_bee_first_query_sent") {
            AnalyticsService.shared.log("ask_bee_first_query_sent", properties: [
                "query_length": trimmed.count
            ])
            UserDefaults.standard.set(true, forKey: "ask_bee_first_query_sent")
        }

        HapticManager.shared.searchSendImpact()

        Task { @MainActor in
            HapticManager.shared.startSearchPulse()
            await aiService.sendMessage(trimmed)

            // Stop haptics based on message state
            if let lastMessage = aiService.messages.last {
                switch lastMessage.state {
                case .complete:
                    HapticManager.shared.stopSearchPulse(success: true)
                case .failed:
                    HapticManager.shared.stopSearchPulse(success: false)
                case .loading:
                    HapticManager.shared.stopSearchPulse(success: false)
                }
            } else {
                HapticManager.shared.stopSearchPulse(success: false)
            }
        }
    }

}

#Preview {
    AskAIView()
        .preferredColorScheme(.light)
}
