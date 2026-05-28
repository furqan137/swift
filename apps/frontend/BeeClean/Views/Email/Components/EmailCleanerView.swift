import SwiftUI

// MARK: - Email Cleaner View (Main Screen)
struct EmailCleanerView: View {
    let showsBackButton: Bool

    @Environment(\.dismiss) private var dismiss
    @StateObject private var emailService = EmailService.shared
    @StateObject private var authService = AuthService.shared
    @StateObject private var undoMgr = EmailUndoManager()
    @State private var showUnsubscribe = false
    @State private var navigateToCategory: GmailCategory?
    @State private var scope: String = "all"

    @State private var gmailEmail: String? = nil
    @State private var profileMismatch = false
    @State private var isBackendOffline = false
    @State private var needsSignIn = false

    private var connectedEmail: String? {
        gmailEmail ?? AuthService.shared.currentUser?.email
    }

    private var totalEmails: Int {
        emailService.totalEmailCount > 0
            ? emailService.totalEmailCount
            : emailService.categories.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        // Scoped NavigationStack — every email-internal push (category
        // detail, Unsubscribe list) lives INSIDE this stack instead of the
        // shared root stack at ContentView level. When the user taps another
        // tab, EmailCleanerView is torn down by SwiftUI's tab swap, this
        // NavigationStack goes with it, and EVERY destination it owned is
        // freed. On return, a fresh NavigationStack mounts with an empty
        // path — the user always lands on the categories root, never on a
        // stale Unsubscribe / category-detail flash.
        //
        // The previous architecture leaked: ContentView held one shared
        // NavigationStack across all tabs, so a destination pushed during a
        // prior email session could survive a tab swap and re-render for a
        // beat when the user came back. Pure per-tab isolation closes that
        // gap. .onAppear resets are kept as a belt for the suspenders so
        // even hot-reload / state-restoration paths can't surface a stale
        // destination.
        NavigationStack {
            ZStack {
                glassBackdrop

                VStack(spacing: 0) {
                    header

                    if emailService.isLoading && emailService.categories.isEmpty {
                        loadingState
                    } else if let error = emailService.error, emailService.categories.isEmpty {
                        EmailErrorView(
                            error: error,
                            isBackendOffline: isBackendOffline,
                            needsSignIn: needsSignIn,
                            isAuthenticated: authService.isAuthenticated,
                            onRetry: { Task { await loadEmailData() } },
                            onSignIn: {
                                Task {
                                    await authService.signInWithGoogle()
                                    if authService.isAuthenticated { await loadEmailData() }
                                }
                            }
                        )
                    } else {
                        categoryList
                    }
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $navigateToCategory) { category in
                EmailCategoryDetailView(category: category, scope: scope)
            }
            .navigationDestination(isPresented: $showUnsubscribe) {
                UnsubscribeListView(scope: scope)
            }
        }
        .undoToast(undoMgr)
        .onAppear {
            // Defensive reset of every navigation binding the email tab owns.
            // ContentView keeps a SINGLE NavigationStack across all tabs, so
            // a destination pushed during a previous email session (tap into
            // Unsubscribe, then tab away) can otherwise still be at the top
            // of the stack when the user returns to email — that was the
            // "email randomly loads Unsubscribe before showing the cards"
            // bug. Resetting both bindings on appear forces the stack back
            // to the categories root every time the email tab is selected.
            showUnsubscribe = false
            navigateToCategory = nil
        }
        .task {
            // Initial load only. Once categories are populated, they stay.
            // No background polling — the user explicitly asked for "stay
            // loaded, no refresh" behavior. A fresh fetch happens only on
            // pull-to-refresh (handled inside the category list) or when
            // the user returns to email after a sign-out / re-auth.
            if emailService.categories.isEmpty && !emailService.isLoading {
                await loadEmailData()
            }
        }
        // NOTE: `.onDisappear` previously called `cancelAllPrefetches()`
        // here. That fires on EVERY hierarchy change — including when the
        // user taps a category tile and the NavigationStack pushes
        // EmailCategoryDetailView ON TOP of this view. Result: the
        // prefetch task that was warming the tapped category's cache got
        // killed JUST before the detail view's `loadMessages` ran, so
        // every category opened cold (Updates and Promotions hit hardest
        // because their backend scans take longest). The prefetches are
        // small (25 msgs each, capped at one task per category) and
        // self-terminate within seconds, so leaving them to finish is
        // strictly cheaper than re-paying the cost on category entry.
    }

    // MARK: - Glass Backdrop
    //
    // Cool blue-lavender → warm light-gray gradient — same stops as the
    // Settings screen so Settings / Email / Compress share one canvas.
    private var glassBackdrop: some View {
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
    }


    // MARK: - Header
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsBackButton {
                Button {
                    HapticManager.shared.arrowNudge(.backward)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .frame(width: 36, height: 36)
                        .background(
                            Circle().fill(Color.white.opacity(0.7))
                        )
                        .overlay(
                            Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Text("Email")
                .font(.custom("Poppins-Bold", size: 28))
                .foregroundColor(Color(hex: "1C1917"))

            Spacer()

            if emailService.isLoading && !emailService.categories.isEmpty {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "A1A1AA")))
                    .scaleEffect(0.7)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    // MARK: - Loading
    private var loadingState: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "6366F1")))
                .scaleEffect(1.1)
            Text("Loading your emails")
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(Color(hex: "71717A"))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Category List
    private var categoryList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 8) {
                ForEach(emailService.categories) { category in
                    EmailCategoryRowView(
                        category: category,
                        isSelected: false,
                        onCheckboxTapped: {},
                        onArrowTapped: { navigateToCategory = category }
                    )
                }

                // Unsubscribe row — same white card as categories, indigo accent on icon
                Button { showUnsubscribe = true } label: {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [Color(hex: "6366F1").opacity(0.20), Color(hex: "6366F1").opacity(0.10)],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                )
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color(hex: "6366F1").opacity(0.22), lineWidth: 0.6)
                            Image(systemName: "bell.slash.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(Color(hex: "6366F1"))
                        }
                        .frame(width: 44, height: 44)

                        Text("Unsubscribe")
                            .font(.custom("Poppins-Bold", size: 19))
                            .foregroundColor(Color(hex: "1C1917"))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)

                        Spacer(minLength: 8)

                        Text(emailService.isSendersLoading && emailService.senders.isEmpty
                             ? "—"
                             : "\(emailService.senders.count)")
                            .font(.custom("Poppins-Bold", size: 16))
                            .foregroundColor(Color(hex: "1C1917"))
                            .monospacedDigit()
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule().fill(Color(hex: "6366F1").opacity(0.12))
                            )

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .heavy))
                            .foregroundColor(Color(hex: "A1A1AA"))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .frame(height: 76)
                    // Match EmailCategoryRowView and the Contacts tiles —
                    // .ultraThinMaterial + top-down white gradient + sheen
                    // border + soft drop shadow, all from the shared
                    // GlassPanel primitive in DesignTokens.swift.
                    .background(GlassPanel(cornerRadius: 18, elevation: .card))
                }
                .buttonStyle(ContactTileButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 140)
        }
        .refreshable {
            async let cats: () = emailService.fetchCategories(scope: scope)
            async let senders: () = emailService.fetchSenders(scope: scope, refresh: true)
            await cats
            await senders
        }
    }

    // MARK: - Load Email Data
    private func loadEmailData() async {
        isBackendOffline = false
        needsSignIn = false

        let hasCachedData = !emailService.categories.isEmpty

        // Always show the loading screen before any network check so the user
        // never sees an instant error flash.
        if !hasCachedData {
            emailService.isLoading = true
            emailService.error = nil
        }

        if !hasCachedData {
            let status = await authService.ensureValidSession()
            switch status {
            case .valid, .reAuthenticated:
                break
            case .backendOffline:
                isBackendOffline = true
                emailService.error = "Cannot reach server. Make sure the backend is running on port 3001."
                emailService.isLoading = false
                return
            case .notSignedIn:
                needsSignIn = true
                emailService.error = "Please sign in with Google to access your emails."
                emailService.isLoading = false
                return
            }
        }

        async let categoriesTask: () = emailService.fetchCategories(scope: scope)
        async let sendersTask: () = emailService.fetchSenders(scope: scope, refresh: true)
        async let profileTask: GmailProfile? = emailService.verifyProfile()

        await categoriesTask
        await sendersTask

        if let profile = await profileTask {
            gmailEmail = profile.email
            profileMismatch = !profile.matches
        }
    }
}

#Preview {
    NavigationStack {
        EmailCleanerView(showsBackButton: false)
    }
    .preferredColorScheme(.light)
}
