import SwiftUI

// MARK: - Contacts View
struct ContactsView: View {
    @StateObject private var viewModel = ContactsViewModel.shared
    @StateObject private var phoneLookup = PhoneLookupService.shared
    @StateObject private var backupService = BackupService.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedCategory: ContactCategory?
    @State private var showPhoneInput = false
    @State private var showBackups = false
    @AppStorage("userPhoneNumber") private var userPhoneNumber = ""

    // Bitepal/Email-mirrored: flat white cards on cool-gray gradient,
    // each card carries its own tint color on the icon badge for
    // visual identity (parity with the Email category cards).
    private static let cardSurface  = Color.white
    private static let cardText     = Color(hex: "1C1917")  // espresso
    private static let cardMuted    = Color(hex: "8A8A8E")  // neutral cool muted

    // Per-category tints — distinct from the Email palette (which uses
    // blue / lavender / orange / green / purple / red / indigo) so the
    // two tabs never feel like color twins.
    private static let duplicatesTint = Color(hex: "14B8A6")   // teal
    private static let incompleteTint = Color(hex: "F43F5E")   // rose
    private static let backupsTint    = Color(hex: "64748B")   // slate
    private static let allTint        = Color(hex: "D946EF")   // fuchsia

    var body: some View {
        ZStack {
            // Bitepal cool-gray gradient — shared across the Contacts /
            // Email / Settings / Compress tabs and every screen they push.
            BitepalCanvas()

            if viewModel.hasAccess {
                authorizedContent
            } else if viewModel.permissionStatus == .denied || viewModel.permissionStatus == .restricted {
                ContactPermissionDeniedView()
            } else {
                ContactPermissionRequestView {
                    Task {
                        let granted = await viewModel.requestPermission()
                        if granted { await viewModel.loadContacts() }
                    }
                }
            }
        }
        .task {
            viewModel.checkPermission()
            if viewModel.hasAccess && viewModel.allContacts.isEmpty {
                await viewModel.loadContacts()
            }
            if userPhoneNumber.isEmpty && !viewModel.allContacts.isEmpty {
                if let myContact = viewModel.detectMyContact(),
                   let firstPhone = myContact.phoneNumbers.first {
                    userPhoneNumber = firstPhone
                }
            }
            if !userPhoneNumber.isEmpty && phoneLookup.lookupResult == nil {
                await phoneLookup.fetchPhoneInfo(phone: userPhoneNumber)
            }
        }
        .fullScreenCover(item: $selectedCategory) { category in
            ContactListView(category: category)
        }
        .sheet(isPresented: $showPhoneInput) {
            PhoneInputSheet(phoneNumber: $userPhoneNumber, isPresented: $showPhoneInput)
        }
        .onChange(of: userPhoneNumber) { _, newValue in
            if !newValue.isEmpty {
                phoneLookup.clear()
                Task { await phoneLookup.fetchPhoneInfo(phone: newValue) }
            } else {
                phoneLookup.clear()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                let oldAccess = viewModel.hasAccess
                viewModel.checkPermission()
                if viewModel.hasAccess && !oldAccess {
                    Task { await viewModel.loadContacts() }
                }
            }
        }
        .hidesBottomNavBar()
        .environment(\.colorScheme, .light)
    }

    // MARK: - Authorized Content
    private var authorizedContent: some View {
        VStack(spacing: 0) {
            // Header — Poppins-Bold (Bitepal-style bold humanist sans).
            // Bundled in BeeClean/Fonts and registered in Info.plist.
            HStack(alignment: .center) {
                Text("Contacts")
                    .font(.custom("Poppins-Bold", size: 28))
                    .foregroundColor(Color(hex: "1C1917"))

                Spacer()

                if viewModel.isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "1C1917")))
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 18)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    // Static-on-arrival tiles. Previous version chained
                    // `appeared` opacity + 8pt rise + 0.30s delay PER tile
                    // and the count itself had a `countRevealDelay` of
                    // 0.35–0.56s on top of that, so the user stared at
                    // dashes for nearly a full second on every visit.
                    // Counts now show immediately and auto-update through
                    // the @Published bindings + `contentTransition(.numericText())`
                    // — same model the email category cards use.
                    ContactTile(
                        icon: "rectangle.on.rectangle.angled",
                        title: "Duplicates",
                        count: viewModel.duplicateCount,
                        tint: Self.duplicatesTint
                    ) { selectedCategory = .duplicates }

                    ContactTile(
                        icon: "person.crop.circle.badge.exclamationmark",
                        title: "Incomplete",
                        count: viewModel.incompleteCount,
                        tint: Self.incompleteTint
                    ) { selectedCategory = .incomplete }

                    ContactTile(
                        icon: "shield.lefthalf.filled",
                        title: "Backups",
                        count: backupService.backups.count,
                        tint: Self.backupsTint
                    ) {
                        showBackups = true
                    }

                    ContactTile(
                        icon: "person.3.fill",
                        title: "All Contacts",
                        count: viewModel.totalContacts,
                        tint: Self.allTint
                    ) { selectedCategory = .all }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 120)
            }
            .refreshable { await viewModel.loadContacts() }
        }
        .fullScreenCover(isPresented: $showBackups) {
            BackupsListView()
        }
    }

}

// MARK: - Contact Tile
//
// Pop-then-navigate row — same pattern as IntelligentPreviewCard and
// EmailCategoryRowView. Vanilla Button press state dismisses the
// instant a finger lifts, which fires in the same frame as the sheet
// presentation, so the user never sees a press cue and the row reads
// as static. Manual `isPressed` pins the dim/scale visual for ~150ms
// before the destination action runs — the row pops, then opens.
private struct ContactTile: View {
    let icon: String
    let title: String
    let count: Int
    let tint: Color
    let action: () -> Void

    @State private var isPressed = false

    private static let cardText = Color(hex: "1C1917")

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
                action()
            }
        } label: {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.20), tint.opacity(0.10)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(tint.opacity(0.25), lineWidth: 0.6)
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(tint)
                }
                .frame(width: 54, height: 54)

                Text(title)
                    .font(.custom("Poppins-Bold", size: 22))
                    .foregroundColor(Self.cardText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)

                HStack(spacing: 10) {
                    Text(formattedCount(count))
                        .font(.custom("Poppins-Bold", size: 24))
                        .foregroundColor(Self.cardText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.3), value: count)

                    // Tinted chevron chip — same SleekArrowChip the Email
                    // rows and YourSpaceRow use. Solid tinted disc reads
                    // far more "tap me" than a flat gray glyph.
                    SleekArrowChip(tint: tint, size: 28)
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 76)
            .background(GlassPanel(cornerRadius: 22, elevation: .card))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.black.opacity(isPressed ? 0.16 : 0))
                    .allowsHitTesting(false)
            )
            .brightness(isPressed ? -0.08 : 0)
            .scaleEffect(isPressed ? 0.96 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func formattedCount(_ count: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: count)) ?? "\(count)"
    }
}

// MARK: - Contact Glass Modifier (used by sub-views)
//
// Chrome-glass surface used by every contact row, duplicate group
// card, and merge-banner pill in the contacts flow. Shares one
// lighting model with the BottomNavBar / MergePreviewView cards so
// the whole app reads as crafted hardware lit from above. Stack
// (bottom up):
//   1. Body gradient (white → warm cream) — lit-from-above cue.
//   2. Top rim-light highlight via .plusLighter — same trick the
//      nav bar uses.
//   3. Bottom inner shadow — a hint of depth at the lower edge so
//      the surface reads as a curved 3D pill, not a flat sticker.
//   4. Outer hairline silhouette — keeps the card crisp against
//      the cool-gray gradient canvas.
//   5. Stacked shadows: tight definition + wide ambient lift.
//      Matches the bar's signature so the two surfaces visibly
//      share one elevation plane.
extension View {
    func contactGlass(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(
                ZStack {
                    // Body — stronger top→bottom ramp so the curvature
                    // reads as real depth instead of a flat sticker.
                    // White → #F4F5F8 (~96% white with cool warmth).
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color(hex: "F4F5F8")
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Top rim-light — bumped to 100% white at the top
                    // edge so the highlight visibly catches light. The
                    // single most effective premium-glass cue.
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white,
                                    Color.white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 1
                        )
                        .blendMode(.plusLighter)

                    // Bottom bevel — bumped 0.06 → 0.10 so the lower
                    // edge has the curved-3D-edge cue, not a flat fade.
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.clear,
                                    Color.black.opacity(0.10)
                                ],
                                startPoint: .center,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.8
                        )

                    // Outer hairline — bumped 0.06 → 0.10 so the silhouette
                    // is crisp against the lavender canvas instead of
                    // disappearing into it.
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
                }
            )
            // Tight definition shadow — bumped 0.06 → 0.10 for clear
            // surface boundary.
            .shadow(color: Color.black.opacity(0.10), radius: 4, y: 2)
            // Wide ambient lift — bumped 0.08/14 → 0.13/20 so the cards
            // visibly float above the lavender ground. Same signature
            // that makes the bottom nav bar and the email row stack pop.
            .shadow(color: Color.black.opacity(0.13), radius: 20, y: 8)
    }
}

// MARK: - Tile Button Style
//
// Stronger press feedback — matches the Quick Access tile darken so
// every tap surface in the app shares one "you tapped this" cue.
// Used by Contacts category tiles, Secret Space card, AND every
// Email category row (EmailCategoryRowView pulls this style too).
struct ContactTileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.10 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(configuration.isPressed ? 0.14 : 0))
                    .allowsHitTesting(false)
            )
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.7),
                       value: configuration.isPressed)
    }
}

#Preview {
    ContactsView()
        .preferredColorScheme(.light)
}
