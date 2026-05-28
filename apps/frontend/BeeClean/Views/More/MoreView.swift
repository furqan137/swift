import SwiftUI
import RevenueCatUI

// MARK: - Navigation Destinations
enum MoreDestination: Hashable {
    case contacts
    case secretSpace
    case savedFinds
    case chargingAnimations
    case dataStorage
    case rateUs
    case settings
}

struct MoreView: View {
    let showsBackButton: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showPaywall = false
    // Programmatic navigation target — set by YourSpaceRow after its
    // pop-then-navigate delay completes. Drives `navigationDestination(item:)`
    // below. The plain `navigationDestination(for:)` registration is
    // kept for any legacy NavigationLink(value:) callers elsewhere.
    @State private var navTarget: MoreDestination?
    @Environment(\.scenePhase) private var scenePhase
    /// Drives the NotificationsSheet half-sheet surfaced from the
    /// bell button in the header.
    @State private var showNotificationsSheet = false
    /// Read the live notification preference so the bell icon swaps
    /// between `bell.fill` (on) and `bell.slash.fill` (off) — tiny
    /// state cue without needing a badge.
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true

    #if DEBUG && targetEnvironment(simulator)
    // Observed directly so the seed-status label live-updates while the
    // async generator chews through ~30 photos + a few short videos.
    @StateObject private var mockSeeder = MockMediaSeeder.shared
    #endif

    init(showsBackButton: Bool = true) {
        self.showsBackButton = showsBackButton
    }

    var body: some View {
        ZStack {
            // Polished canvas — light keeps BitePal off-white; dark mode
            // swaps the prior flat near-black for a layered glass surface
            // (base + top sheen + warm accent halo + hairline grain) so
            // the page reads as premium glass instead of a dead black hole.
            personalHubCanvas

            VStack(spacing: 0) {
                // Header sized + padded to match the Progress tab so both
                // flagship pages share one typographic system.
                HStack(spacing: 12) {
                    if showsBackButton {
                        Button {
                            HapticManager.shared.arrowNudge(.backward)
                            dismiss()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.foreground)
                                .frame(width: 40, height: 40)
                                .background(headerCircleFill)
                        }
                    }

                    Text("Personal Hub")
                        .font(.custom("Poppins-Bold", size: 32))
                        .foregroundColor(.foreground)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Spacer()

                    // Notifications quick-access bell — 40pt to match the
                    // 32pt title weight; icon size + adaptive fill so the
                    // chip reads on the glass-polish dark canvas too.
                    Button {
                        HapticManager.shared.buttonTap()
                        showNotificationsSheet = true
                    } label: {
                        Image(systemName: notificationsEnabled ? "bell.fill" : "bell.slash.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.foreground)
                            .frame(width: 40, height: 40)
                            .background(headerCircleFill)
                    }
                    .accessibilityLabel("Notification settings")
                }
                .padding(.horizontal, 6)
                .padding(.top, 12)
                .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        // YOUR SPACE — Quick Access-style container with
                        // Contacts + Secret Space + Recents as inner rows.
                        // Each row carries a live backend-sourced badge.
                        YourSpaceCard(onSelect: { dest in
                            navTarget = dest
                        })

                        #if DEBUG && targetEnvironment(simulator)
                        // Simulator-only tools — stripped from device
                        // and Release builds by the compile-time guards.
                        MoreSectionLabel(title: "Simulator Tools")
                            .padding(.top, 4)

                        simulatorMockSeedCard
                        #endif
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 100)
                }
                // Pull-to-refresh re-syncs every backend store the hub
                // surfaces — Contacts, Recents, and the vault stays
                // live since `loadManifestAsync` re-runs whenever the
                // singleton is touched on `.active` (see below).
                .refreshable {
                    await refreshHubStores()
                }
            }
        }
        .navigationBarHidden(true)
        .navigationDestination(for: MoreDestination.self) { destination in
            destinationView(for: destination)
        }
        .navigationDestination(item: $navTarget) { destination in
            destinationView(for: destination)
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView()
                .onPurchaseCompleted { _ in showPaywall = false }
                .onRestoreCompleted { _ in showPaywall = false }
        }
        .sheet(isPresented: $showNotificationsSheet) {
            NotificationsSheet()
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
        }
        // Initial load — make sure every hub store is warm so the
        // row badges (Contacts dupes, Vault saved, Recents new) all
        // populate the first time the tab opens.
        .task {
            await refreshHubStores()
        }
        // App returning to the foreground: re-pull so a cleanup or
        // import that happened while we were backgrounded is reflected.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshHubStores() }
            }
        }
    }

    // MARK: - Polished canvas + adaptive header chip
    //
    // Dark mode previously fell back to a flat `Color.background`
    // (~#0B0B0E) which read as a dead black hole behind the white
    // cards. New treatment layers a deep slate base + a soft top sheen
    // + a warm honey accent halo + a hairline grain veil so the canvas
    // reads as polished glass rather than dead black. Light mode is
    // unchanged — keeps the BitePal off-white the rest of the app uses.
    @ViewBuilder
    private var personalHubCanvas: some View {
        // Cool blue-lavender → warm light-gray gradient. Identical
        // stops to the Email / Settings / Compress glass backdrop so
        // every secondary tab shares one unified canvas.
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

    /// Adaptive circle fill for header glyph buttons (chevron / bell).
    /// Light mode keeps the warm surfaceLight tile; dark mode uses a
    /// hairline-stroked lifted-glass surface so the button reads on the
    /// new polished canvas without sinking into the slate.
    @ViewBuilder
    private var headerCircleFill: some View {
        // Outline bumped to a flat 14%-black 1pt stroke — the earlier
        // 4%→9% gradient at 0.5pt was practically invisible against
        // the gray hub canvas, so the user couldn't tell where the
        // bell button's edge was. Same hairline opacity the Settings
        // chevron-back button uses, so chrome stays consistent.
        Circle()
            .fill(Color.white)
            .overlay(
                Circle().stroke(
                    Color.black.opacity(0.14),
                    lineWidth: 1
                )
            )
    }

    /// Unified refresh path for every backend store the Personal Hub
    /// shows badges for. Each call site (initial `.task`, pull-to-
    /// refresh, scenePhase active) routes through here so the hub
    /// stays consistent no matter how the user comes back.
    private func refreshHubStores() async {
        // Contacts — pulls the address book + recomputes duplicate
        // groups. Guarded by the manager's own permission gate, so a
        // user who never granted access just no-ops.
        await ContactsViewModel.shared.loadContacts()
        // SecretVaultManager and SavedFindsStore load themselves on
        // init / publish via @ObservedObject; their badges in
        // YourSpaceCard stay in sync without explicit pulls here.
    }

    @ViewBuilder
    private func destinationView(for destination: MoreDestination) -> some View {
        switch destination {
        case .contacts: ContactsView().hidesBottomNavBar()
        case .secretSpace: SecretSpaceView().hidesBottomNavBar()
        case .savedFinds: SavedFindsView().hidesBottomNavBar()
        case .chargingAnimations: ChargingAnimationsView()
        case .dataStorage: DataStorageView()
        case .rateUs: RateUsView()
        case .settings: SettingsView()
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    // MARK: - Simulator-only seeder card
    @ViewBuilder
    private var simulatorMockSeedCard: some View {
        Button {
            Task { await mockSeeder.seed() }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [Color.categoryPurple.opacity(0.18), Color.categoryPurple.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)
                    Image(systemName: mockSeeder.isSeeding ? "hourglass" : "photo.stack.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.categoryPurple)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(mockSeeder.isSeeding ? "Seeding mock library…" : "Seed Mock Photos")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.foreground)
                    Text(mockSeederSubtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.mutedForeground)
                        .lineLimit(2)
                }

                Spacer()

                if mockSeeder.isSeeding {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.categoryPurple)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.categoryPurple.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(mockSeeder.isSeeding)
    }

    private var mockSeederSubtitle: String {
        if mockSeeder.isSeeding {
            return mockSeeder.statusLine
        }
        if let result = mockSeeder.lastResult {
            return "Last run: \(result.totalAssets) assets — \(result.summary)"
        }
        return "Add procedural photos & videos so every category renders"
    }
    #endif
}

// MARK: - Premium Upgrade Card
private struct MorePremiumCard: View {
    let action: () -> Void
    @State private var shimmer: CGFloat = -1

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "00D4AA").opacity(0.2), Color(hex: "A78BFA").opacity(0.1)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 48, height: 48)

                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "00D4AA"), Color(hex: "A78BFA")],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Unlock Premium")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.foreground)
                    Text("Smart cleaning, vault, animations & more")
                        .font(.system(size: 13))
                        .foregroundColor(.mutedForeground)
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "00D4AA"), Color(hex: "00B4D8")],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }
            .padding(16)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white)
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "00D4AA").opacity(0.08), Color(hex: "A78BFA").opacity(0.05), Color.clear],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            )
                        )
                    // Shimmer
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [Color.clear, Color.white.opacity(0.06), Color.clear],
                                startPoint: UnitPoint(x: shimmer - 0.3, y: 0),
                                endPoint: UnitPoint(x: shimmer + 0.3, y: 1)
                            )
                        )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(
                        LinearGradient(
                            colors: [Color(hex: "00D4AA").opacity(0.35), Color(hex: "A78BFA").opacity(0.2), Color.border.opacity(0.3)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color(hex: "00D4AA").opacity(0.10), radius: 16, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                shimmer = 2
            }
        }
    }
}

// MARK: - Your Space Card
//
// Mirrors QuickAccessCard on the Charging dashboard: white container
// with a deep-gold header, gold-gradient hairline, soft lift shadow,
// and tinted-icon row tiles for Contacts, Secret Space, and Recents.
// Each row carries a live badge sourced from the corresponding
// backend store so the hub feels alive when the user opens it.
private struct YourSpaceCard: View {
    let onSelect: (MoreDestination) -> Void

    @ObservedObject private var contacts = ContactsViewModel.shared
    @ObservedObject private var vault = SecretVaultManager.shared
    @ObservedObject private var savedFinds = SavedFindsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("YOUR SPACE")
                .font(.custom("Poppins-Bold", size: 11.5))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundColor(QuickAccessCard.headerColor)
                .lineLimit(1)

            // Trailing badges deliberately removed per the BitePal-pure
            // redesign — the row title + chevron is the canonical
            // affordance, and the counter chips ("12", "2 saved", etc.)
            // added noise that competed with the icon column. The
            // counts now surface inside each destination's own screen
            // header instead. Pass `nil` for `badge` on every row to
            // keep the API while suppressing the visual.
            VStack(spacing: 10) {
                YourSpaceRow(
                    destination: .contacts,
                    icon: "person.2.fill",
                    title: "Contacts",
                    tint: .categoryGreen,
                    badge: nil,
                    onSelect: onSelect
                )
                YourSpaceRow(
                    destination: .secretSpace,
                    icon: "lock.fill",
                    title: "Secret Space",
                    tint: .categorySlate,
                    badge: nil,
                    onSelect: onSelect
                )
                YourSpaceRow(
                    destination: .savedFinds,
                    icon: "bookmark.fill",
                    title: "Saved Finds",
                    tint: Color(hex: "FFC648"),
                    badge: nil,
                    onSelect: onSelect
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            // Adaptive surface — `Color.card` is white in light env and
            // slate dark in dark env. The warm honey hairline stroke
            // below keeps its light-mode treatment; dark mode swaps to
            // a subtle off-white hairline so the edge still reads.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.card)
        )
        .overlay(YourSpaceCardHairline())
        .shadow(color: Color.black.opacity(0.10), radius: 18, x: 0, y: 8)
    }

    // MARK: - Live badges (sourced from the corresponding managers)

    /// Contacts: surface the two actionable counts — duplicate groups
    /// and contacts missing key info (no name/phone/email). When both
    /// are present, the badge carries both so the user sees the full
    /// state at a glance instead of only the dupes count masking the
    /// incomplete pile underneath. Falls back to the total contact
    /// count when nothing needs attention.
    private var contactsBadge: String? {
        guard contacts.permissionStatus == .authorized else { return nil }
        let dupes = contacts.duplicateGroups.count
        let missing = contacts.incompleteCount
        switch (dupes > 0, missing > 0) {
        case (true, true):   return "\(dupes) dup · \(missing) missing"
        case (true, false):  return "\(dupes) dupes"
        case (false, true):  return "\(missing) missing"
        case (false, false):
            let total = contacts.allContacts.count
            return total > 0 ? "\(total)" : nil
        }
    }

    /// Secret Space: count of vaulted items.
    private var vaultBadge: String? {
        let count = vault.items.count
        return count > 0 ? "\(count) saved" : nil
    }

    /// Saved Finds: count of bookmarked photos/videos the user has
    /// captured from any approved Photos/Videos cleanup category.
    private var savedFindsBadge: String? {
        let count = savedFinds.count
        return count > 0 ? "\(count) saved" : nil
    }
}

/// Card hairline that swaps the warm-honey gradient for a subtle
/// off-white stroke in dark mode. Light mode keeps the original
/// honey-tinted edge so the card reads like a polished gold-rim tile.
private struct YourSpaceCardHairline: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        if colorScheme == .dark {
            shape.stroke(Color.white.opacity(0.10), lineWidth: 0.8)
        } else {
            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.95),
                        Color(hex: "CFAF5F").opacity(0.55),
                        Color(hex: "7A5C2E").opacity(0.25)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.1
            )
        }
    }
}

// Sleek inner card inside YourSpaceCard — each destination gets its
// own bordered surface with a tinted icon container and a sleek
// chevron capsule. Premium nested-card aesthetic.
private struct YourSpaceRow: View {
    let destination: MoreDestination
    let icon: String
    let title: String
    let tint: Color
    /// Live count badge sourced from the row's manager. Hidden when nil.
    var badge: String? = nil
    let onSelect: (MoreDestination) -> Void

    // Manual press flag — same pop-then-navigate pattern as
    // ContactTile / EmailCategoryRowView / IntelligentPreviewCard.
    // NavigationLink's built-in press visual ends the instant the
    // push transition starts, so the row reads as static. Pinning
    // the dim/scale for 150ms makes the tap visibly land.
    @State private var isPressed = false

    var body: some View {
        Button {
            HapticManager.shared.impact(.light)
            withAnimation(.spring(response: 0.18, dampingFraction: 0.7)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                    isPressed = false
                }
                onSelect(destination)
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.20), tint.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(tint.opacity(0.22), lineWidth: 0.5)
                        )
                        .frame(width: 46, height: 46)
                        .shadow(color: tint.opacity(0.18), radius: 8, x: 0, y: 3)

                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(tint)
                }

                Text(title)
                    .font(.custom("Poppins-Bold", size: 17))
                    .foregroundStyle(Color.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if let badge {
                    // Faded neutral badge — the previous tinted
                    // background + stroke read as a loud per-row
                    // accent. Neutral gray text on a barely-there
                    // gray capsule keeps the count legible without
                    // shouting; tint stays on the row's icon + arrow.
                    Text(badge)
                        .font(.custom("Poppins-Medium", size: 11))
                        .tracking(0.2)
                        .foregroundColor(Color(hex: "8C92A4"))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.04)))
                        .padding(.trailing, 4)
                        .accessibilityLabel("\(title) badge: \(badge)")
                }

                SleekArrowChip(tint: tint, size: 26)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.6
                    )
                    .blendMode(.plusLighter)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.foreground.opacity(0.08), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 8, x: 0, y: 3)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(isPressed ? 0.16 : 0))
                    .allowsHitTesting(false)
            )
            .brightness(isPressed ? -0.08 : 0)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sleek Arrow Chip
//
// Light tinted disc with a colored chevron — matches the email page's
// count-pill aesthetic. Soft category-tinted background, no shadow,
// chevron in the saturated tint. Used across Quick Access tiles,
// YourSpaceRow, MediaCleanupCard, Compress, Email.
struct SleekArrowChip: View {
    let tint: Color
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
                .frame(width: size, height: size)

            Image(systemName: "chevron.right")
                .font(.system(size: size * 0.46, weight: .heavy))
                .foregroundStyle(tint)
        }
    }
}

// MARK: - Section Label
private struct MoreSectionLabel: View {
    let title: String

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.mutedForeground)
                .tracking(1.0)
            Spacer()
        }
        .padding(.top, 4)
    }
}

// MARK: - Navigation Card
private struct MoreNavCard: View {
    let destination: MoreDestination
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var darkIcon: Bool = false

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: 16) {
                ZStack {
                    if darkIcon {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black)
                            .frame(width: 48, height: 48)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: [iconColor.opacity(0.15), iconColor.opacity(0.06)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(iconColor.opacity(0.15), lineWidth: 0.5)
                            )
                            .shadow(color: iconColor.opacity(0.15), radius: 8)
                            .frame(width: 48, height: 48)
                    }
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(darkIcon ? .white : iconColor)
                }

                if subtitle.isEmpty {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.foreground)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.foreground)
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.mutedForeground)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.mutedForeground)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
            )
            // Top rim-light — same lit-from-above treatment Quick Access
            // tiles use, so the More section's cards share one lighting
            // model with the Charging dashboard above.
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.85),
                                Color.white.opacity(0.0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.5
                    )
                    .blendMode(.plusLighter)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Standalone ToolCardView (kept for reuse elsewhere)
struct ToolCardView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(
                            LinearGradient(
                                colors: [iconColor.opacity(0.15), iconColor.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(iconColor.opacity(0.15), lineWidth: 0.5)
                        )
                        .shadow(color: iconColor.opacity(0.15), radius: 8)
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(iconColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.foreground)
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.mutedForeground)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.mutedForeground)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

#Preview {
    NavigationStack {
        MoreView()
    }
    .preferredColorScheme(.light)
}
