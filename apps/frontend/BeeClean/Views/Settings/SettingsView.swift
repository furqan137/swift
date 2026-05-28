import SwiftUI
import RevenueCatUI
import UserNotifications
import StoreKit
import MessageUI

// MARK: - SettingsView
//
// Cal-AI inspired redesign — replaces the prior warm-cream glass treatment
// with a clean off-white canvas, pure white cards, soft shadows (no glass
// material), subtle colored icon tiles, and generous whitespace.
//
// Sections (in order):
//   1. Profile hero card (avatar + name + email + PRO chip + stats strip)
//   2. PERSONALIZATION  — Notifications, Haptic Feedback, Theme, Daily Goal, Chart Color
//   3. ACCOUNT          — Manage Subscription (Pro), Connected Email
//   4. SUPPORT          — Rate, Share, Help & FAQ
//   5. LEGAL & ABOUT    — Privacy, Terms, Version
//   6. Destructive card — Rerun Onboarding, Sign Out, Delete Account
//
// All previously-shipping behavior preserved (notifications toggle,
// haptics toggle, paywall, manage subscription, sign out, FAQ, privacy,
// terms, streak detail, RevenueCat customer center) plus new prefs
// (theme override, daily commitment goal, chart-color shortcut, mailto-
// based account deletion satisfying App Store Guideline 5.1.1(v)).

struct SettingsView: View {
    // MARK: - Persisted prefs

    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("hapticFeedback") private var hapticsEnabled = true
    @AppStorage(ThemeService.userOverrideKey) private var themeOverrideRaw: String = ThemeService.UserOverride.light.rawValue
    @AppStorage("preferences.dailyItemsGoal") private var dailyItemsGoal: Int = 10
    @AppStorage("preferences.dailyBytesGoal") private var dailyBytesGoal: Int = 100_000_000
    @AppStorage("progress.heroChartPaletteRaw") private var heroChartPaletteRaw: String = ChartPalette.honey.rawValue
    @AppStorage("progress.bestDaySparkPaletteRaw") private var bestDaySparkPaletteRaw: String = ChartPalette.honey.rawValue
    /// Bee mascot name — same `userName` key the dashboard uses (see
    /// `NameEditOverlay` in ChargingView). Settings is now the canonical
    /// rename surface; binding here lets the trailing-side value in the
    /// row stay live as the user types in the sheet, and lets the sheet
    /// pass through the same binding it was originally built to take.
    @AppStorage("userName") private var beeName: String = ""

    // MARK: - Services

    @StateObject private var authService = AuthService.shared
    @StateObject private var subscriptionService = SubscriptionService.shared
    @ObservedObject private var stats = HiveStatsManager.shared
    @ObservedObject private var loc = LocalizationService.shared

    // MARK: - UI state

    @Environment(\.dismiss) private var dismiss

    @State private var showSignOutConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var showPaywall = false
    @State private var showStreakDetail = false
    @State private var showLanguageSheet = false
    @State private var actualNotificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var navDestination: SettingsDestination?

    enum SettingsDestination: Hashable {
        case faq
        case privacy
        case terms
        case manageSubscription
        case dailyGoal
        /// Pushed when the user taps the Bee's name row. Owns its own
        /// subpage with the inline editor (replaces the old sheet).
        case beeRename
    }

    // MARK: - Derived

    private var versionString: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Warm cream canvas — pulled from the BeeClean app palette
            // (Color.background = #FBF9F6 light / #000 dark) so Settings
            // shares the same ground tone as ChargingView, QuickAccessCard,
            // and every other premium surface. Cards float on this warmth
            // rather than on the previous flat off-white.
            Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                settingsHeader

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Profile hero card retired — the BitePal-pure
                        // redesign opens straight with the Pro upsell so
                        // the upgrade beat is the first thing the user
                        // sees instead of a stats strip. Account info
                        // (email + sign out) moved down into the Account
                        // section card; user-display-name rename still
                        // available via the legacy `showEditNameSheet`
                        // path if reintroduced later.
                        if !subscriptionService.isPro {
                            upgradeBanner
                        }

                        // PREFERENCES — 4 rows, Cal-AI tight.
                        // Notifications + Haptics stay as inline toggles
                        // (one-tap convenience). Theme + Daily Goal show
                        // their current value inline; tap pushes the
                        // existing picker pages.
                        sectionCard(title: BCLoc.preferences.tr) {
                            toggleRow(icon: "bell.fill",
                                      color: .categorySky,
                                      label: BCLoc.notifications.tr,
                                      isOn: notificationsBinding)
                            divider
                            toggleRow(icon: "iphone.radiowaves.left.and.right",
                                      color: .categoryViolet,
                                      label: BCLoc.hapticFeedback.tr,
                                      isOn: hapticsBinding)
                            divider
                            // Theme picker removed — dark mode was
                            // retired app-wide. Every surface is light.
                            languageRow
                            divider
                            // Bee's name — mirrors BitePal's "Raccoon's
                            // name" row. Bee mascot artwork sits in the
                            // leading icon slot instead of an SF Symbol,
                            // current name on the trailing side, chevron
                            // to signal a push into the rename sheet.
                            // The dashboard headline used to own this
                            // path; moving it here gives the user one
                            // canonical place to rename the mascot.
                            beeNameRow
                        }

                        // ACCOUNT — BitePal-aligned: leading row shows
                        // the connected email (read-only, mirrors
                        // BitePal's "Email paulrejijoseph@gmail.com"
                        // row), then Manage Subscription for Pro users,
                        // then Sign Out as a destructive footer row.
                        // The previous profile-hero email surface was
                        // retired with the hero card; this row is the
                        // canonical place the user sees their account.
                        sectionCard(title: BCLoc.account.tr) {
                            if let email = connectedEmail {
                                emailRow(email)
                                divider
                            }
                            if subscriptionService.isPro {
                                navRow(icon: "sparkles",
                                       color: .categoryHoney,
                                       label: BCLoc.manageSubscription.tr,
                                       value: nil,
                                       destination: .manageSubscription)
                                divider
                            }
                            destructiveRow(icon: "rectangle.portrait.and.arrow.right",
                                           label: BCLoc.signOut.tr,
                                           action: { showSignOutConfirm = true })
                        }

                        // SUPPORT — 3 rows. Rate / Share dropped:
                        // Cal AI doesn't beg for ratings in Settings,
                        // and Share belongs in an empty-state CTA
                        // somewhere, not a permanent row.
                        sectionCard(title: BCLoc.supportAndLegal.tr) {
                            navRow(icon: "questionmark.circle.fill",
                                   color: .categoryTeal,
                                   label: BCLoc.helpAndFaq.tr,
                                   value: nil,
                                   destination: .faq)
                            divider
                            navRow(icon: "hand.raised.fill",
                                   color: .categorySlate,
                                   label: BCLoc.privacyPolicy.tr,
                                   value: nil,
                                   destination: .privacy)
                            divider
                            navRow(icon: "doc.text.fill",
                                   color: .categorySlate,
                                   label: BCLoc.termsOfService.tr,
                                   value: nil,
                                   destination: .terms)
                        }

                        // Tiny footer — version + Delete Account link.
                        // Cal AI puts legal-tier stuff at the very
                        // bottom in muted small text so it doesn't
                        // compete with real prefs. Delete Account
                        // preserved as a confirmation-gated mailto
                        // for App Store 5.1.1(v) compliance.
                        settingsFooter
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 48)
                }
            }
        }
        .hidesBottomNavBar()
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $navDestination) { dest in
            switch dest {
            case .faq: FAQView()
            case .privacy: PrivacyPolicyView()
            case .terms: TermsOfServiceView()
            case .manageSubscription: CustomerCenterView()
            case .dailyGoal: DailyGoalSettingsView()
            case .beeRename: BeeRenameView(beeName: $beeName)
            }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
                .onPurchaseCompleted { _ in showPaywall = false }
                .onRestoreCompleted { _ in showPaywall = false }
        }
        .fullScreenCover(isPresented: $showStreakDetail) {
            StreakDetailView(onClose: { showStreakDetail = false })
        }
        // The display-name and bee-rename sheets were both retired with
        // the BitePal-pure redesign. Bee rename pushes `BeeRenameView`
        // via `SettingsDestination.beeRename`; user display-name is no
        // longer editable from Settings (Google sign-in name is the
        // canonical surface).
        .sheet(isPresented: $showLanguageSheet) {
            LanguageSettingsView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(BCLoc.signOutConfirmTitle.tr, isPresented: $showSignOutConfirm) {
            Button(BCLoc.signOut.tr, role: .destructive) {
                HapticManager.shared.notify(.warning)
                AuthService.shared.signOut()
            }
            Button(BCLoc.cancel.tr, role: .cancel) {}
        }
        .alert("Delete Account?", isPresented: $showDeleteAccountConfirm) {
            Button("Continue", role: .destructive) {
                HapticManager.shared.notify(.warning)
                openDeleteAccountMail()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, all your data, and your subscription. This action cannot be undone. We'll open Mail so you can confirm the request with our support team.")
        }
        .onAppear { checkNotificationStatus() }
    }

    // MARK: - Header

    private var settingsHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                HapticManager.shared.arrowNudge(.backward)
                dismiss()
            } label: {
                glassChevronPill()
            }
            Text(BCLoc.settings.tr)
                .font(.custom("Poppins-Bold", size: 24))
                .foregroundColor(.foreground)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 16)
    }

    // MARK: - Profile hero card
    //
    // White card. Top row: avatar + name + email on the left, PRO chip
    // (or nothing) on the right. Stats strip below with a hairline divider
    // separating it from the header row.

    // Profile hero card / avatar / PRO chip / stats strip + statColumn
    // / statDivider were all retired with the BitePal-pure Settings
    // redesign. The dashboard's HiveScoreCard / TodaysCleanupCard now
    // surface streak + bytes-saved in-flow on Charging, and the email
    // moved into the Account section's read-only `emailRow`. The
    // identity-related state (`userDisplayNameOverride`, `displayName`
    // helpers) and the modal `EditUserNameSheet` were removed along
    // with the card since there's no more name-editable surface on
    // Settings (the bee rename now pushes `BeeRenameView` instead).

    // MARK: - Upgrade banner (free users only)

    /// White-card Upgrade row — drops the full-bleed honey gradient so
    /// the page no longer reads as a yellow-dominant CTA. Honey is now
    /// only on the small leading sparkles tile + the compact trailing
    /// "Upgrade" pill (`LinearGradient.honeySoft`, less saturated than
    /// the old `honeyDeep`). Same tap behavior — opens the paywall.
    // MARK: - Pro Banner (BitePal-aligned)
    //
    // Replaces the previous thin-row banner with a hero card built off
    // BitePal's "Try BitePal Plus" treatment: full-width rounded card,
    // bold dark headline left-aligned over the upper half, a solid black
    // "Get Pro" pill chip directly under it, and the bee mascot artwork
    // bleeding off the right edge so the card reads as a deliberate
    // upsell surface rather than just another settings row. Cal AI
    // contributes the soft cream → honey gradient backdrop + the
    // hairline gold rim, so the card sits warmly inside the warm-cream
    // canvas without screaming for attention.
    private var upgradeBanner: some View {
        Button {
            HapticManager.shared.primaryCommit()
            showPaywall = true
        } label: {
            ZStack {
                // Card backdrop — softer cream → muted honey wash that
                // no longer pops out against the gray Settings canvas.
                // The previous `#FFF6DA → #FFE7A6` saturation made the
                // banner read as a yellow shout; tightening to
                // `#FFF3D4 → #F5D88B` keeps the warm-honey identity but
                // sits more comfortably in the section stack. Border
                // stays gold so the brand cue is intact.
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "FFF3D4"),
                                Color(hex: "F5D88B")
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(Color(hex: "CFAF5F").opacity(0.35),
                                    lineWidth: 0.8)
                    )
                    .shadow(color: Color(hex: "C4850A").opacity(0.08),
                            radius: 14, y: 6)

                // Foreground layout — VERTICALLY centered headline +
                // CTA pill on the left, mascot on the right. The
                // outer HStack pins each half to its column; inside
                // the left VStack everything is `.center`-aligned so
                // the Upgrade pill sits centered under its headline
                // instead of pinned to the leading rail.
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .center, spacing: 12) {
                        Text(BCLoc.unlockProTitle.tr)
                            .font(.custom("Poppins-Bold", size: 21))
                            .foregroundColor(Color(hex: "1C1917"))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        // Dark pill CTA — same espresso ink the chat
                        // FAB now uses, tighter padding so the pill
                        // reads as a refined chip rather than a heavy
                        // button.
                        Text(BCLoc.upgrade.tr)
                            .font(.custom("Poppins-Bold", size: 14))
                            .foregroundColor(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color(hex: "1C1917"))
                            )
                            .shadow(color: Color.black.opacity(0.20),
                                    radius: 8, y: 3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.leading, 6)

                    // Mascot column — wider visible area and bigger
                    // mascot now that the card has more height. Bleeds
                    // off the right edge for the BitePal-style crop.
                    Image("bee_card_mascot")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 140)
                        .padding(.trailing, -4)
                        .padding(.vertical, -6)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 22)
            }
            // Taller card — 130pt felt cramped, the new 156pt gives
            // the headline + centered pill + mascot enough room to
            // breathe so the banner reads as a hero card rather than a
            // pinched row.
            .frame(height: 156)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Section card

    /// Warm-toned section card with a one-line subtitle under the title.
    /// Subtitle is optional — pass nil to keep the original single-line
    /// header. Card surface is the same `Color.card → 0.94` gradient used
    /// by the hero, just with a softer shadow so the hierarchy reads
    /// hero-first.
    private func sectionCard<Content: View>(title: String,
                                            subtitle: String? = nil,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Inspo-card style: a single muted mid-grey line above
            // each card, sentence-cased, no tracking. The optional
            // subtitle is intentionally dropped — the inspo layout
            // doesn't use one. Callers can still pass it but it now
            // renders as a small secondary line for back-compat.
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.custom("Poppins-Medium", size: 15))
                    .foregroundColor(.mutedForeground)
                if let subtitle {
                    Text(subtitle)
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(.foregroundSecondary)
                }
            }
            .padding(.leading, 4)
            .padding(.bottom, 10)

            VStack(spacing: 0) {
                content()
            }
            .background(cardBackground)
        }
    }

    private var cardBackground: some View {
        glassCardBackground(.section)
    }

    // MARK: - Row builders

    /// Thin wrapper around the top-level `settingsIconTile` so the row
    /// builders below still read fluently. Polish lives in the free
    /// function so sub-views (Theme picker, Daily Goal) share the exact
    /// same recipe.
    private func iconTile(_ symbol: String, color: Color) -> some View {
        settingsIconTile(symbol, color: color)
    }

    /// Language row — visually identical to a `navRow` but its
    /// tap presents `LanguageSettingsView` as a modal sheet (with
    /// drag indicator + X-close) rather than pushing onto the nav
    /// stack. Matches the inspo screenshot's sheet-style picker.
    private var languageRow: some View {
        Button {
            HapticManager.shared.buttonTap()
            showLanguageSheet = true
        } label: {
            HStack(spacing: 14) {
                iconTile("globe", color: .categoryTeal)
                Text(BCLoc.language.tr)
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.foreground)
                Spacer(minLength: 8)
                Text(loc.current.nativeName)
                    .font(.custom("Poppins-Bold", size: 13))
                    .foregroundColor(.foregroundSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.mutedForeground)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    /// Bee's name row — pushes into the dedicated `BeeRenameView`
    /// subpage instead of presenting a sheet. The push reads as a
    /// genuine settings navigation (matches Language, FAQ, Privacy
    /// Policy, etc.) rather than the prior modal interruption.
    private var beeNameRow: some View {
        Button {
            HapticManager.shared.buttonTap()
            navDestination = .beeRename
        } label: {
            HStack(spacing: 14) {
                beeMascotIconTile
                Text(BCLoc.beeName.tr)
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.foreground)
                Spacer(minLength: 8)
                Text(beeDisplayName)
                    .font(.custom("Poppins-Bold", size: 13))
                    .foregroundColor(.foregroundSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.mutedForeground)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    /// Refined bee-row tile. Renders the painted bee avatar
    /// (`BeeNameAvatar`) in a softly-honey-tinted square — same
    /// painted character used on the BeeRenameView header, so the
    /// row tile and the subpage hero read as the same identity.
    private var beeMascotIconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.categoryHoney.opacity(0.20))
            Image("BeeNameAvatar")
                .resizable()
                .scaledToFit()
                .padding(2)
        }
        .frame(width: 32, height: 32)
    }

    /// Trailing-side text for `beeNameRow`. Falls back to the same
    /// "BeeBuddy" default the dashboard uses so the row never reads
    /// empty on a fresh install.
    private var beeDisplayName: String {
        let trimmed = beeName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "BeeBuddy" : trimmed
    }

    /// Read-only Email row for the Account section. Mirrors BitePal's
    /// `Email <address>` row — envelope icon on the left, label in the
    /// middle, the user's connected Google email on the right. No
    /// chevron, no tap: the email isn't editable here (sign-out + new
    /// sign-in is the rename path). Matches the visual cadence of the
    /// other rows so the row column lines up cleanly inside the card.
    private func emailRow(_ email: String) -> some View {
        HStack(spacing: 14) {
            iconTile("envelope.fill", color: .categorySky)
            Text(BCLoc.email.tr)
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.foreground)
            Spacer(minLength: 8)
            Text(email)
                .font(.custom("Poppins-Medium", size: 13))
                .foregroundColor(.foregroundSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    /// Row that opens a destination on tap.
    private func navRow(icon: String,
                        color: Color,
                        label: String,
                        value: String?,
                        destination: SettingsDestination) -> some View {
        Button {
            HapticManager.shared.buttonTap()
            navDestination = destination
        } label: {
            HStack(spacing: 14) {
                iconTile(icon, color: color)
                Text(label)
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.foreground)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .font(.custom("Poppins-Bold", size: 13))
                        .foregroundColor(.foregroundSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.mutedForeground)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    /// Row whose tap fires an action (no navigation).
    private func actionRow(icon: String,
                           color: Color,
                           label: String,
                           action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.buttonTap()
            action()
        } label: {
            HStack(spacing: 14) {
                iconTile(icon, color: color)
                Text(label)
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.foreground)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.mutedForeground)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    /// Row hosting a SwiftUI Toggle on the trailing side.
    private func toggleRow(icon: String,
                           color: Color,
                           label: String,
                           isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            iconTile(icon, color: color)
            Text(label)
                .font(.custom("Poppins-Medium", size: 16))
                .foregroundColor(.foreground)
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                // Espresso ink instead of the prior `.categorySky`
                // (iOS-default blue) — matches the rest of the app's
                // chrome (chat FAB, Upgrade pill, primary action buttons)
                // so the on-state reads as brand-consistent dark ink
                // rather than a stock iOS blue.
                .tint(Color(hex: "1C1917"))
        }
        .padding(.horizontal, 16)
        .frame(height: 60)
    }

    /// Destructive row — red gradient icon tile, destructive label, no
    /// chevron. Uses the adaptive `Color.destructive` so it stays
    /// legible in dark mode.
    private func destructiveRow(icon: String,
                                label: String,
                                action: @escaping () -> Void) -> some View {
        Button {
            HapticManager.shared.buttonTap()
            action()
        } label: {
            HStack(spacing: 14) {
                iconTile(icon, color: .destructive)
                Text(label)
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.destructive)
                Spacer(minLength: 8)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
    }

    /// Version row — read-only trailing value + tap-to-copy.
    /// Tiny footer at the bottom of Settings — version text + a
    /// destructive Delete Account link. Replaces the old versionRow
    /// (which was a full row with tap-to-copy gimmick — Cal AI puts
    /// legal-tier info as small footer text so it doesn't compete
    /// with real preferences). Delete Account still routes through
    /// the existing mailto path for App Store 5.1.1(v) compliance.
    private var settingsFooter: some View {
        VStack(spacing: 14) {
            // Destructive capsule pill — replaces the old underlined
            // text link. Same visual weight as the SaveFindButton
            // capsule, just tinted with the destructive palette so
            // there's no chance of confusing it with a primary CTA.
            Button {
                HapticManager.shared.buttonTap()
                showDeleteAccountConfirm = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5, weight: .bold))
                    Text(BCLoc.deleteAccount.tr)
                        .font(.custom("Poppins-Bold", size: 12.5))
                        .tracking(0.2)
                }
                .foregroundColor(.destructive)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(Color.destructive.opacity(0.10))
                )
                .overlay(
                    Capsule().stroke(Color.destructive.opacity(0.28), lineWidth: 0.8)
                )
            }
            .buttonStyle(RowPressStyle())
            .accessibilityLabel("Delete Account")

            Text("BeeClean \(versionString)")
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(.mutedForeground)
                .monospacedDigit()
        }
        .padding(.top, 18)
        .frame(maxWidth: .infinity)
    }

    /// Hairline between rows inside a card — inset so it starts after
    /// Hairline between rows inside a card — inset so it starts just
    /// past the icon (28pt glyph + 14pt spacing + 16pt outer padding
    /// = 58pt, rounded to 58 to match the new flat-icon layout).
    /// Uses the adaptive `Color.border` token so legibility holds in
    /// both light and dark modes.
    private var divider: some View {
        Rectangle()
            .fill(Color.border)
            .frame(height: 0.5)
            .padding(.leading, 58)
    }

    // MARK: - Destructive card

    // (destructiveCard removed — Sign Out now lives inline in the
    // Account section; Rerun Onboarding was a debug-only behavior
    // dropped per Cal-AI guardrail; Delete Account moved to the
    // tiny settingsFooter above. versionCopiedOverlay also removed
    // since the version-tap-to-copy gimmick is gone.)

    // MARK: - Bindings & helpers

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { notificationsEnabled },
            set: { newValue in
                HapticManager.shared.selection()
                notificationsEnabled = newValue
                if newValue {
                    requestNotificationPermission()
                }
            }
        )
    }

    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { hapticsEnabled },
            set: { newValue in
                // Fire BEFORE writing the new value so the off→on tick
                // still uses the prior state's gate. Without this, the
                // first selection() on enable used the just-flipped
                // `isEnabled = true` and the off→on flip ticked twice
                // (once when prior state was on with no audible
                // change, once when state flipped). Simpler approach:
                // fire on either direction, let `selection()`'s own
                // `isEnabled` gate decide if it actually plays.
                HapticManager.shared.selection()
                hapticsEnabled = newValue
            }
        )
    }

    private var heroPalette: ChartPalette {
        ChartPalette(rawValue: heroChartPaletteRaw) ?? .honey
    }

    private var dailyGoalLabel: String {
        let items = dailyItemsGoal > 0 ? dailyItemsGoal : 10
        let bytes = dailyBytesGoal > 0 ? Int64(dailyBytesGoal) : 100_000_000
        return "\(items) items · \(formatBytes(bytes))"
    }

    /// Read-only email surfaced by the Account section's `emailRow`.
    /// Nil when the user isn't signed in (the row is skipped).
    /// `displayName` / `displayEmail` / `initials` were dropped with
    /// the profile hero card.
    private var connectedEmail: String? {
        guard authService.isAuthenticated,
              let email = authService.currentUser?.email,
              !email.isEmpty
        else { return nil }
        return email
    }

    // MARK: - Number / byte formatting

    private func formatNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000     { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1_000_000 { return "\(bytes / 1_000) KB" }
        if bytes < 1_000_000_000 {
            return String(format: "%.0f MB", Double(bytes) / 1_000_000)
        }
        return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }

    // MARK: - Notifications

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.actualNotificationStatus = settings.authorizationStatus
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    if !granted {
                        // System denied — bounce to Settings so the user
                        // can flip it on at the OS layer. We don't fight
                        // the system status here.
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        notificationsEnabled = false
                    }
                    checkNotificationStatus()
                }
            }
    }

    // MARK: - Actions

    private func requestReview() {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
        else { return }
        SKStoreReviewController.requestReview(in: scene)
    }

    private func openDeleteAccountMail() {
        // Apple's Guideline 5.1.1(v) requires an in-app account-deletion
        // mechanism. Until we ship a backend endpoint, mailto with the
        // user's id pre-filled is the documented interim. The support
        // address is the canonical one — change here if it ever moves.
        let to = "support@beeclean.app"
        let subject = "Account Deletion Request"
        let body: String = {
            let userId = authService.currentUser?.id ?? "(no user id)"
            let email = authService.currentUser?.email ?? "(no email)"
            return """
            Please delete my BeeClean account and all associated data.

            User id: \(userId)
            Email: \(email)
            App version: \(versionString)
            """
        }()

        var components = URLComponents()
        components.scheme = "mailto"
        components.path = to
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body)
        ]
        if let url = components.url {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - RowPressStyle
//
// Subtle visual feedback on row press — dims the row to 0.55 opacity
// for the press duration without scaling (Cal AI doesn't scale rows).
struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// `ThemeSettingsView` was deleted alongside the rest of the dark-mode
// retirement. The theme picker row is gone from Settings and the only
// remaining ThemeService surface (`mode`/`scheduleMode`) is pinned to
// `.light`. `ThemeService.UserOverride` is preserved as a stub enum so
// any persisted preference still decodes cleanly, but no Settings
// subpage references it anymore.

// MARK: - DailyGoalSettingsView
//
// Two stepper rows — items + bytes. The values feed straight into the
// HiveStatsManager goal accessors which now read from these keys.
private struct DailyGoalSettingsView: View {
    @AppStorage("preferences.dailyItemsGoal") private var items: Int = 10
    @AppStorage("preferences.dailyBytesGoal") private var bytes: Int = 100_000_000
    @Environment(\.dismiss) private var dismiss

    private let itemRange = 1...100
    private let byteStep = 10_000_000      // 10 MB
    private let byteMin = 10_000_000       // 10 MB
    private let byteMax = 2_000_000_000    // 2 GB

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()
            VStack(spacing: 0) {
                miniHeader(title: "Daily Goal", dismiss: dismiss)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Clear this day by hitting EITHER target — items or bytes. Whichever rail you reach first counts for the streak.")
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(.foregroundSecondary)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)

                        VStack(spacing: 0) {
                            stepperRow(label: "Items per day",
                                       value: "\(items > 0 ? items : 10)",
                                       icon: "target",
                                       tint: .primaryLight,
                                       decrement: {
                                           if items > itemRange.lowerBound { items -= 1 }
                                       },
                                       increment: {
                                           if items < itemRange.upperBound { items += 1 }
                                       },
                                       canDecrement: items > itemRange.lowerBound,
                                       canIncrement: items < itemRange.upperBound)
                            Rectangle()
                                .fill(Color.border)
                                .frame(height: 0.5)
                                .padding(.leading, 68)
                            stepperRow(label: "Bytes per day",
                                       value: formatBytes(Int64(bytes > 0 ? bytes : 100_000_000)),
                                       icon: "shippingbox.fill",
                                       tint: .categoryAmber,
                                       decrement: {
                                           if bytes > byteMin { bytes -= byteStep }
                                       },
                                       increment: {
                                           if bytes < byteMax { bytes += byteStep }
                                       },
                                       canDecrement: bytes > byteMin,
                                       canIncrement: bytes < byteMax)
                        }
                        .background(glassCardBackground(.section))
                        .padding(.horizontal, 20)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .hidesBottomNavBar()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func stepperRow(label: String,
                            value: String,
                            icon: String,
                            tint: Color,
                            decrement: @escaping () -> Void,
                            increment: @escaping () -> Void,
                            canDecrement: Bool,
                            canIncrement: Bool) -> some View {
        HStack(spacing: 14) {
            settingsIconTile(icon, color: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.foreground)
                Text(value)
                    .font(.custom("Poppins-Bold", size: 15))
                    .foregroundColor(.primaryLight)
                    .monospacedDigit()
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                stepperButton(symbol: "minus",
                              enabled: canDecrement,
                              action: { HapticManager.shared.selection(); decrement() })
                stepperButton(symbol: "plus",
                              enabled: canIncrement,
                              action: { HapticManager.shared.selection(); increment() })
            }
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 68)
    }

    private func stepperButton(symbol: String,
                               enabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(enabled ? .foreground : .mutedForeground.opacity(0.5))
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(Color.surfaceLight)
                )
                .overlay(
                    Circle().stroke(Color.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        if bytes < 1_000_000_000 {
            return String(format: "%.0f MB", Double(bytes) / 1_000_000)
        }
        return String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
    }
}

// MARK: - ConnectedEmailDetailView
//
// Small detail screen with one destructive action: Disconnect Email.
// Today disconnecting routes through `AuthService.shared.signOut()` —
// future work could split the Google scope from the BeeClean scope so
// the user keeps their BeeClean account but unlinks Gmail. Kept simple
// for now since the app's auth model treats the two as one identity.
private struct ConnectedEmailDetailView: View {
    @ObservedObject private var authService = AuthService.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color(hex: "F8F8F6").ignoresSafeArea()
            VStack(spacing: 0) {
                miniHeader(title: "Connected Email", dismiss: dismiss)
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(hex: "10B981").opacity(0.12))
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(Color(hex: "10B981"))
                                }
                                .frame(width: 34, height: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(authService.currentUser?.email ?? "—")
                                        .font(.custom("Poppins-Bold", size: 15))
                                        .foregroundColor(Color(hex: "0F172A"))
                                    Text("Google")
                                        .font(.custom("Poppins-Medium", size: 12))
                                        .foregroundColor(Color(hex: "8C92A4"))
                                }
                                Spacer(minLength: 8)
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.04), radius: 16, y: 4)
                            )
                        }
                        .padding(.horizontal, 20)

                        Text("Disconnecting will sign you out of BeeClean entirely. Your local data is preserved on this device; sign back in to resume.")
                            .font(.custom("Poppins-Medium", size: 13))
                            .foregroundColor(Color(hex: "6B7280"))
                            .padding(.horizontal, 20)

                        Button {
                            HapticManager.shared.notify(.warning)
                            // Dismiss BEFORE signOut so the pop animation
                            // runs on a view that still exists. signOut()
                            // triggers a root-view remount that would
                            // otherwise leave dismiss() targeting an
                            // already-torn-down navigation context.
                            dismiss()
                            DispatchQueue.main.async {
                                AuthService.shared.signOut()
                            }
                        } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color(hex: "EF4444").opacity(0.12))
                                    Image(systemName: "rectangle.portrait.and.arrow.right.fill")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundColor(Color(hex: "EF4444"))
                                }
                                .frame(width: 34, height: 34)
                                Text("Disconnect Email")
                                    .font(.custom("Poppins-Medium", size: 16))
                                    .foregroundColor(Color(hex: "EF4444"))
                                Spacer(minLength: 8)
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
                            .contentShape(Rectangle())
                            .background(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: Color.black.opacity(0.04), radius: 16, y: 4)
                            )
                            .padding(.horizontal, 20)
                        }
                        .buttonStyle(RowPressStyle())
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 40)
                }
            }
        }
        .hidesBottomNavBar()
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - Mini header
//
// Shared chrome for the small sub-settings pages (Theme, Daily Goal,
// Chart Color, Connected Email). Same back chevron + title style as
// the main Settings header but extracted so each sub-view doesn't
// re-implement it.
private func miniHeader(title: String, dismiss: DismissAction) -> some View {
    HStack(alignment: .center, spacing: 12) {
        Button {
            HapticManager.shared.arrowNudge(.backward)
            dismiss()
        } label: {
            glassChevronPill()
        }
        Text(title)
            .font(.custom("Poppins-Bold", size: 22))
            .foregroundColor(.foreground)
        Spacer()
    }
    .padding(.horizontal, 20)
    .padding(.top, 8)
    .padding(.bottom, 16)
}

/// Glass back-chevron pill — pure white fill, hairline gradient rim,
/// top white inner highlight (the "lit hardware" tell), soft shadow.
/// Shared between `settingsHeader` and `miniHeader` so every back
/// affordance matches the new card surface treatment.
func glassChevronPill() -> some View {
    Image(systemName: "chevron.left")
        .font(.system(size: 16, weight: .bold))
        .foregroundColor(.foreground)
        .frame(width: 40, height: 40)
        .background(
            Circle().fill(Color.card)
        )
        .overlay(
            Circle().strokeBorder(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.04),
                        Color.black.opacity(0.09)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.5
            )
        )
        .overlay(
            Circle().strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.55), Color.clear],
                    startPoint: .top,
                    endPoint: .center
                ),
                lineWidth: 1
            )
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, y: 3)
        .shadow(color: Color.black.opacity(0.03), radius: 2, y: 1)
}

// MARK: - Glass card background
//
// Single recipe for every white card surface in Settings: hero card,
// section cards, and every sub-view (Theme, Daily Goal, Notifications
// sheet). Pure white fill (no gradient — gradients render
// inconsistently across short/tall cards, see the long-form comment
// in `Theme/DesignTokens.swift` GlassPanel for why). Polish comes
// from a hairline gradient rim (lit-from-above) + tiered layered
// shadow, not from translucency. Two elevation tiers:
//
//   .hero    — anchors the page, stronger shadow
//   .section — softer shadow, sits under the hero in the hierarchy
//
// All sub-views call `.background(glassCardBackground(.section))`
// for visual parity.
enum SettingsCardElevation {
    case hero
    case section
}

/// 38pt rounded glass icon tile — soft tint base, crisp tinted
/// Flat monochrome row glyph — matches the "Support & Legal" inspo
/// card style. Single SF Symbol at 20pt regular in `.foreground`,
/// in a fixed 28pt-wide frame so label baselines line up across
/// rows. No tile, no gradient, no border. The legacy `color:` arg
/// is kept on the signature for source compatibility with call
/// sites that still pass a tint — we deliberately ignore it.
func settingsIconTile(_ symbol: String, color: Color = .foreground) -> some View {
    Image(systemName: symbol)
        .font(.system(size: 20, weight: .regular))
        .foregroundColor(.foreground)
        .frame(width: 28, height: 28)
}

func glassCardBackground(_ elevation: SettingsCardElevation,
                         cornerRadius: CGFloat = 22) -> some View {
    AdaptiveCardBackground(elevation: elevation, cornerRadius: cornerRadius)
}

/// Reads the local colorScheme env so light + dark each get a bespoke
/// recipe. Light: glass-gradient (top specular + bottom soft). Dark:
/// stealth — flat deep-black fill, thin off-white edge, soft shadow.
private struct AdaptiveCardBackground: View {
    let elevation: SettingsCardElevation
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if colorScheme == .dark {
            shape
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "232328"), Color(hex: "1A1A1D")],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.75))
                .overlay(alignment: .top) {
                    Capsule()
                        .fill(Color.white.opacity(0.14))
                        .frame(height: 1)
                        .padding(.horizontal, 36)
                        .padding(.top, 0.6)
                        .allowsHitTesting(false)
                }
                .shadow(color: Color.black.opacity(elevation == .hero ? 0.45 : 0.30),
                        radius: elevation == .hero ? 14 : 10, y: 4)
        } else {
            let ambientOpacity: Double = elevation == .hero ? 0.07 : 0.05
            let ambientRadius: CGFloat = elevation == .hero ? 22 : 16
            let ambientY: CGFloat = elevation == .hero ? 8 : 5
            let contactOpacity: Double = elevation == .hero ? 0.05 : 0.03
            shape
                .fill(
                    LinearGradient(
                        colors: [Color.white, Color(hex: "F7F7F8")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    shape
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.85), Color.clear],
                                startPoint: .top,
                                endPoint: UnitPoint(x: 0.5, y: 0.45)
                            )
                        )
                        .allowsHitTesting(false)
                )
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [Color.black.opacity(0.05), Color.black.opacity(0.10)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                )
                .shadow(color: Color.black.opacity(ambientOpacity),
                        radius: ambientRadius, y: ambientY)
                .shadow(color: Color.black.opacity(contactOpacity),
                        radius: 2, y: 1)
        }
    }
}

// NOTE: ShareSheet is declared in
// Views/Contacts/Components/ContactListView.swift — same target, internal
// visibility, identical signature, so we reuse it here instead of
// redeclaring.

// MARK: - NotificationsSheet
//
// Single-purpose sheet for managing push notifications. Surfaced
// from two places:
//   • The bell button in the MoreView header (quick access)
//   • Optionally the Notifications row in Settings (kept the inline
//     toggle there too for one-tap convenience)
//
// The sheet owns the same system-permission binding logic the old
// SettingsView row used — reads live `UNAuthorizationStatus`,
// requests permission on `notDetermined`, opens the system Settings
// app on `denied`. Status banner copy reflects the live state.

struct NotificationsSheet: View {
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @Environment(\.dismiss) private var dismiss
    @State private var actualStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 18)

            toggleCard
                .padding(.horizontal, 20)

            statusSection
                .padding(.horizontal, 20)
                .padding(.top, 18)

            Spacer(minLength: 0)

            if actualStatus == .denied {
                openSystemSettingsButton
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
        }
        .background(Color.background.ignoresSafeArea())
        .onAppear { refreshStatus() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notifications")
                .font(.custom("Poppins-Bold", size: 22))
                .foregroundColor(.foreground)
            Text("Stay on top of your cleanup ritual.")
                .font(.custom("Poppins-Medium", size: 13))
                .foregroundColor(.foregroundSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var toggleCard: some View {
        let tint: Color = notificationsEnabled ? Color.categorySky : Color.mutedForeground
        return HStack(spacing: 14) {
            // Bell tile — same gradient icon-tile recipe used everywhere
            // else in Settings so the sheet feels native, just sized up
            // slightly (44pt) since it anchors a much taller sheet card.
            Image(systemName: notificationsEnabled ? "bell.fill" : "bell.slash.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.18), tint.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 0.7)
                )

            Text("Push notifications")
                .font(.custom("Poppins-Bold", size: 16))
                .foregroundColor(.foreground)

            Spacer()

            Toggle("", isOn: Binding(
                get: { notificationsEnabled },
                set: { newValue in
                    if newValue { requestPermission() }
                    else {
                        notificationsEnabled = false
                        if actualStatus == .authorized { openAppSettings() }
                    }
                }
            ))
            .labelsHidden()
            .tint(.categorySky)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(glassCardBackground(.section))
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATUS")
                .font(.custom("Poppins-Bold", size: 10.5))
                .tracking(0.6)
                .foregroundColor(.mutedForeground)

            HStack(spacing: 10) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 8, height: 8)
                Text(statusCopy)
                    .font(.custom("Poppins-Medium", size: 13))
                    .foregroundColor(.foregroundSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.surfaceLight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.border, lineWidth: 0.5)
            )
        }
    }

    private var openSystemSettingsButton: some View {
        Button {
            openAppSettings()
        } label: {
            HStack(spacing: 8) {
                Text("Open System Settings")
                    .font(.custom("Poppins-Bold", size: 14))
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 12, weight: .heavy))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(Color.foreground))
            .shadow(color: Color.black.opacity(0.20), radius: 14, y: 5)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status copy + color

    private var statusCopy: String {
        switch actualStatus {
        case .authorized, .provisional, .ephemeral:
            return "Authorized — you'll get reminders when it's time to clean."
        case .denied:
            return "Notifications are off in System Settings. Open Settings to re-enable."
        case .notDetermined:
            return "Tap the toggle above to enable reminders."
        @unknown default:
            return "Unknown — tap the toggle to refresh."
        }
    }

    private var statusDotColor: Color {
        switch actualStatus {
        case .authorized, .provisional, .ephemeral: return .success
        case .denied:        return .destructive
        case .notDetermined: return .foregroundSecondary
        @unknown default:    return .mutedForeground
        }
    }

    // MARK: - System hooks

    private func refreshStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                actualStatus = settings.authorizationStatus
                if settings.authorizationStatus == .denied {
                    notificationsEnabled = false
                }
            }
        }
    }

    private func requestPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .notDetermined:
                    UNUserNotificationCenter.current().requestAuthorization(
                        options: [.alert, .badge, .sound]
                    ) { granted, _ in
                        DispatchQueue.main.async {
                            notificationsEnabled = granted
                            actualStatus = granted ? .authorized : .denied
                        }
                    }
                case .denied:
                    notificationsEnabled = false
                    openAppSettings()
                case .authorized, .provisional, .ephemeral:
                    notificationsEnabled = true
                @unknown default: break
                }
            }
        }
    }

    private func openAppSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - BeeRenameView (pushed subpage)
//
// Dedicated Settings child for renaming the bee mascot. Replaces the
// prior modal sheet so the editor reads as a real navigation step in
// the Settings hierarchy — back chevron in the top-left, hero title,
// inline text field, a Save pill, and a hint subtitle. Lighter than
// the old half-screen sheet because there's nothing else on the
// canvas competing for attention.
//
// Visual contract — mirrors the rest of the redesigned Settings
// surface so this page reads as a sibling of the Preferences and
// Account cards, not a one-off:
//   • Warm cream `Color.background` canvas
//   • A single white card holds the editor (24pt corner radius,
//     same `Color.card` token Preferences uses)
//   • Honey-gold mascot hex above the input — the brand mark this
//     page is about
//   • Charcoal Save pill at the bottom of the card
//
// Save semantics: trims whitespace, writes through the bound
// `@AppStorage("userName")` and pops back to Settings on commit. The
// trailing whitespace trim is the same rule the dashboard's
// `displayName` getter applies so the two surfaces never disagree.
private struct BeeRenameView: View {
    @Binding var beeName: String
    @State private var draft: String = ""
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.background.ignoresSafeArea()

            VStack(spacing: 0) {
                miniHeader

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        // Edge-to-edge box — touches the screen
                        // borders so the rename card matches the rest
                        // of the dashboard's sleek full-bleed
                        // treatment. Hint pulled — the Save button is
                        // self-explanatory.
                        editorCard
                            .padding(.horizontal, 0)
                            .padding(.top, 24)

                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 32)
                }
            }
        }
        .hidesBottomNavBar()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            draft = beeName.trimmingCharacters(in: .whitespaces)
            // Focus on appear so the user lands in editing mode
            // immediately — no extra tap needed to bring up the
            // keyboard. The 0.25s delay lets the push animation
            // settle so the keyboard rise doesn't fight it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isFocused = true
            }
        }
    }

    // MARK: - Mini header

    private var miniHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                HapticManager.shared.arrowNudge(.backward)
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.foreground)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle().fill(Color.white)
                    )
                    .overlay(
                        Circle().stroke(Color.black.opacity(0.06),
                                        lineWidth: 0.6)
                    )
                    .shadow(color: Color.black.opacity(0.08),
                            radius: 6, y: 2)
            }
            .buttonStyle(.plain)

            Text(BCLoc.beeName.tr)
                .font(.custom("Poppins-Bold", size: 22))
                .foregroundColor(.foreground)

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Editor card

    private var editorCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Inline hex + headline row — moved the brand glyph
            // INTO the same horizontal line as the title text so the
            // sheet reads as "this is a focused naming task," not a
            // ceremonial profile-edit screen. Tighter, sleeker, and
            // matches the rest of the Settings detail-card hierarchy.
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "FFC648"),
                                    Color(hex: "F5A623")
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 40, height: 40)
                    Image("BeeNameAvatar")
                        .resizable()
                        .scaledToFit()
                        .padding(2)
                        .frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Name your bee")
                        .font(.custom("Poppins-Bold", size: 17))
                        .foregroundColor(.foreground)
                    Text("Shown above the bee on your dashboard.")
                        .font(.custom("Poppins-Medium", size: 12))
                        .foregroundColor(.foregroundSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            // Inline rounded text field — amber-tinted border on
            // focus to match the new amber identity used by the
            // brand glyph + the dashboard's primary CTA.
            HStack(spacing: 10) {
                TextField("BeeBuddy", text: $draft)
                    .font(.custom("Poppins-Medium", size: 16))
                    .foregroundColor(.foreground)
                    .submitLabel(.done)
                    .focused($isFocused)
                    .onSubmit { commit() }
                if !draft.isEmpty {
                    Button {
                        HapticManager.shared.selection()
                        draft = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.mutedForeground.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: "F8F6F2"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isFocused
                            ? Color(hex: "FFC648")
                            : Color.black.opacity(0.08),
                        lineWidth: isFocused ? 1.5 : 0.6
                    )
            )

            saveButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity)
        .background(
            // No rounded corners — edge-to-edge full-bleed card.
            Rectangle()
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.05), radius: 14, y: 6)
        )
        .overlay(
            Rectangle()
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Save button

    private var saveButton: some View {
        Button(action: commit) {
            Text(BCLoc.save.tr)
                .font(.custom("Poppins-Bold", size: 16))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    // Amber CTA matching the dashboard's "Start Quick
                    // Cleanup" button so the Save action carries the
                    // same primary-action visual identity.
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: "FFC648"))
                )
                .shadow(color: Color(hex: "F5A623").opacity(0.25),
                        radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .disabled(commitDisabled)
        .opacity(commitDisabled ? 0.4 : 1.0)
    }

    private var commitDisabled: Bool {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        let current = beeName.trimmingCharacters(in: .whitespaces)
        return trimmed == current
    }

    // MARK: - Hint

    private var hint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.mutedForeground.opacity(0.6))
                .padding(.top, 1)
            Text("Tap Save to apply your change.")
                .font(.custom("Poppins-Medium", size: 12))
                .foregroundColor(.mutedForeground)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Commit

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard trimmed != beeName.trimmingCharacters(in: .whitespaces) else {
            HapticManager.shared.selection()
            return
        }
        HapticManager.shared.primaryCommit()
        beeName = trimmed
        dismiss()
    }
}
