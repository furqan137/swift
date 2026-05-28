import SwiftUI

// MARK: - Palette (scoped to permission views)
// Trust-first palette. Explicitly zero honey / gold anywhere on this screen
// — this is a permissions page, it should read like a bank's privacy prompt,
// not a storybook. Icon tiles are a cool graphite, the single accent color
// is a muted trust-blue reserved for the shield/lock glyphs, and everything
// else is white + near-black + neutral gray.
private enum BeePalette {
    static let ink        = Color(hex: "0F172A")   // near-black slate
    static let inkSoft    = Color(hex: "64748B")   // secondary text
    static let surface    = Color.white
    static let divider    = Color(hex: "EEF2F6")
    static let stroke     = Color(hex: "E2E8F0")
    /// Slate icon-tile fill — replaces the old gold hexagons
    static let tileFill   = Color(hex: "F1F5F9")
    static let tileStroke = Color(hex: "E2E8F0")
    /// Single accent color for trust glyphs (shield, lock, checkmark).
    /// Apple-ish muted blue — reads as "secure" without feeling branded.
    static let trustBlue  = Color(hex: "2563EB")
    static let trustBlueSoft = Color(hex: "EFF6FF")
}

// MARK: - Contact Permission Request View
struct ContactPermissionRequestView: View {
    let onRequestAccess: () -> Void
    @State private var appeared = false

    var body: some View {
        // Non-scrolling layout. The page is meant to be seen at a glance,
        // not swiped through — it's the single most important trust moment
        // in the onboarding flow, and scrolling breaks the "fits on one
        // screen" read that makes it feel like a system prompt.
        //
        // Layout structure:
        //   [ hero ]              bleeds into the top safe area
        //   [ headline ]
        //   [ proof stamps ]
        //   [ feature card ]
        //   [ Spacer ]            flexes to absorb any leftover height
        //   [ CTA + fineprint ]   pinned just above the tab bar inset
        //
        // The bottom safeAreaInset reserves 110pt so the floating tab bar +
        // FAB cluster can never overlap the CTA or fineprint.
        VStack(spacing: 0) {
            hero

            headline
                .padding(.top, 20)
                .padding(.bottom, 12)

            proofStamps
                .padding(.bottom, 14)

            featureCard
                .padding(.horizontal, 20)

            Spacer(minLength: 10)

            ctaButton
                .padding(.horizontal, 20)
                // ~40pt of clear gradient below the CTA matches the airy
                // breathing room the Email "Connect your inbox" view leaves
                // above the floating nav pill. The hero size is dialed down
                // (width / 2.0 below) to keep the total VStack content
                // inside the ~690pt budget, so the larger bottom padding
                // never pushes the CTA into the nav bar's reserved zone.
                .padding(.bottom, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Note: ContentView.swift wraps `ContactsView()` with its own
        // `.safeAreaInset(edge: .bottom, 132pt)` that already reserves
        // clearance for the floating `BottomNavBar`. We deliberately do
        // NOT add another safeAreaInset here — stacking two at the same
        // edge made the whole page compute 242pt of reserved bottom area,
        // which broke the nav bar's perceived rendering region and let
        // the gradient/white background win over the pill.
        //
        // Background is intentionally clear so the parent `ContactsView`
        // light-blue→neutral gradient shows through. A solid white
        // background here made the shared floating `BottomNavBar` pill
        // (also white over material) vanish for lack of contrast — Home
        // gets the pill clearly because its cartoon scene is textured.
        .background(Color.clear)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .task {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: Hero — full-bleed-width banner, seated below the status bar.
    //
    // Sizing uses an explicit height derived from screen width — earlier
    // versions tried `Color.clear.aspectRatio(.fit)` but `Color.clear` has
    // no intrinsic size, so in a VStack without a parent height it could
    // collapse to zero and the banner would fail to render at all. Locking
    // the height to `screenWidth / 1.55` guarantees it draws.
    //
    // Source asset is 1.67:1; at 1.55:1 display, `.fill` trims only a
    // sliver off the leftmost/rightmost flowers while keeping the bee,
    // antennae, and full ground intact.
    //
    // We deliberately do NOT bleed into the top safe area — the bee's head
    // was getting tucked under the Dynamic Island on Pro devices. Seating
    // the banner below the status bar keeps the subject fully visible and
    // gives the whole page some welcome breathing room at the top.
    private var hero: some View {
        // 2.0 aspect ratio shrinks the banner just enough that — combined
        // with the 28pt top pad — there's room for the larger 40pt bottom
        // pad on the CTA, matching the airy nav-bar clearance on the
        // Email "Connect your inbox" screen. Bee + grass + flowers stay
        // fully visible at this ratio.
        let heroHeight = (UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.screen.bounds.width ?? 393) / 2.0
        return Image("bee_running")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            .clipped()
            .clipShape(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 0,
                        bottomLeading: 32,
                        bottomTrailing: 32,
                        topTrailing: 0
                    ),
                    style: .continuous
                )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 14, y: 6)
            // 28pt clears the Dynamic Island on Pro devices (status bar
            // height ~14pt + safe area top ~14pt = enough margin) without
            // burning the 38pt of extra space the old 66pt was eating.
            .padding(.top, 28)
            .opacity(appeared ? 1 : 0)
            .scaleEffect(appeared ? 1 : 0.985, anchor: .top)
            .animation(.spring(response: 0.6, dampingFraction: 0.82), value: appeared)
    }

    // MARK: Headline + sub
    //
    // Split across two Text views instead of a single string with `\n`.
    // A parent with a narrow content width can silently collapse an
    // embedded newline to a space and then truncate the whole thing to one
    // line with an ellipsis — splitting into independent rows prevents that.
    // `fixedSize(horizontal: false, vertical: true)` guarantees full
    // multi-line height even if a future parent layout squeezes the width.
    private var headline: some View {
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text("Take control of")
                Text("your contacts")
            }
            .font(.system(size: 26, weight: .black))
            .foregroundColor(BeePalette.ink)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            Text("BeeClean works entirely on your iPhone.\nYour contacts never leave your device.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(BeePalette.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(.easeOut(duration: 0.45).delay(0.06), value: appeared)
    }

    // MARK: Proof Stamps — three micro-pills that read like privacy policy stamps.
    // This replaces the gold-hex "PRIVATE BY DESIGN" banner. The visual
    // pattern is deliberately lifted from pages like 1Password / Apple
    // privacy — small capsules in a row, slate tone, no decoration. The
    // repetition (three consistent stamps) is what builds trust, not
    // imagery.
    private var proofStamps: some View {
        HStack(spacing: 8) {
            proofStamp(icon: "iphone", text: "On-device")
            proofStamp(icon: "lock.fill", text: "Never uploaded")
            proofStamp(icon: "xmark.icloud", text: "No servers")
        }
        .padding(.horizontal, 20)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 6)
        .animation(.easeOut(duration: 0.45).delay(0.12), value: appeared)
    }

    private func proofStamp(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundColor(BeePalette.inkSoft)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            Capsule()
                .fill(BeePalette.tileFill)
        )
        .overlay(
            Capsule()
                .stroke(BeePalette.tileStroke, lineWidth: 1)
        )
    }

    // MARK: Feature Card — three flat rows in one card
    private var featureCard: some View {
        VStack(spacing: 0) {
            featureRow(
                icon: "person.2.fill",
                title: "Find & merge duplicates",
                subtitle: "Spot the same person saved twice",
                index: 0
            )
            divider
            featureRow(
                icon: "questionmark.app.dashed",
                title: "Spot incomplete entries",
                subtitle: "Missing names, numbers, or emails",
                index: 1
            )
            divider
            featureRow(
                icon: "sparkles",
                title: "One-tap quick clean",
                subtitle: "Recommended fixes, ready to apply",
                index: 2
            )
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BeePalette.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BeePalette.stroke, lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(BeePalette.divider)
            .frame(height: 1)
            .padding(.leading, 70)
    }

    private func featureRow(icon: String, title: String, subtitle: String, index: Int) -> some View {
        HStack(spacing: 14) {
            // Flat slate tile, no gold, no gradient, no glyph-shaped frame.
            // A soft rounded square reads as "system utility row" which is
            // what we want here — not "branded feature card".
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(BeePalette.tileFill)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(BeePalette.tileStroke, lineWidth: 1)
                )
                .overlay(
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(BeePalette.ink)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundColor(BeePalette.ink)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BeePalette.inkSoft)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -8)
        .animation(.easeOut(duration: 0.45).delay(0.20 + Double(index) * 0.06), value: appeared)
    }

    // MARK: CTA — clean black button, no honey glow
    private var ctaButton: some View {
        Button(action: onRequestAccess) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)

                Text("Allow Contacts Access")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(BeePalette.ink)
                    .shadow(color: Color.black.opacity(0.18), radius: 14, y: 8)
            )
        }
        .buttonStyle(ContactTileButtonStyle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.32), value: appeared)
    }

}

// MARK: - Contact Permission Denied View
struct ContactPermissionDeniedView: View {
    @State private var appeared = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                hero
                    .padding(.top, 32)
                    .padding(.bottom, 26)

                headline
                    .padding(.bottom, 26)

                stepCard
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)

                openSettingsButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)

                fineprint
                    .padding(.horizontal, 32)
            }
            // See ContactPermissionRequestView.body — same rationale, the
            // floating tab bar + FAB eat roughly 132pt off the bottom.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 132)
            }
        }
        // Clear so the parent `ContactsView` gradient shows through —
        // keeps the shared `BottomNavBar` pill contrasted the same way
        // the Home tab gets it. See the request view for full rationale.
        .background(Color.clear)
        .environment(\.colorScheme, .light)
        .preferredColorScheme(.light)
        .task {
            withAnimation(.easeOut(duration: 0.5)) { appeared = true }
        }
    }

    // MARK: Hero — trust-blue lock circle, no gold.
    // The denied screen needs to feel like iOS's own "access restricted"
    // prompt: a single glyph in a soft-tinted circle, centered, calm.
    // The muted trust-blue accent is the ONLY non-neutral color on the
    // whole screen and is reserved for this security glyph.
    private var hero: some View {
        ZStack {
            Circle()
                .fill(BeePalette.trustBlueSoft)
                .frame(width: 120, height: 120)

            Image(systemName: "lock.shield.fill")
                .font(.system(size: 48, weight: .semibold))
                .foregroundColor(BeePalette.trustBlue)
        }
        .opacity(appeared ? 1 : 0)
        .scaleEffect(appeared ? 1 : 0.92)
        .animation(.spring(response: 0.55, dampingFraction: 0.78), value: appeared)
    }

    // MARK: Headline
    private var headline: some View {
        VStack(spacing: 10) {
            Text("Contacts access\nis turned off")
                .font(.system(size: 28, weight: .black))
                .foregroundColor(BeePalette.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Text("Re-enable contacts in iOS Settings to find\nduplicates and clean up your address book.")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(BeePalette.inkSoft)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
        .padding(.horizontal, 24)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .animation(.easeOut(duration: 0.45).delay(0.06), value: appeared)
    }

    // MARK: Step Card — flat checklist of how to re-enable
    private var stepCard: some View {
        VStack(spacing: 0) {
            stepRow(number: "1", title: "Open Settings", subtitle: "Tap the button below", index: 0)
            divider
            stepRow(number: "2", title: "Tap BeeClean", subtitle: "Find it in the app list", index: 1)
            divider
            stepRow(number: "3", title: "Toggle Contacts on", subtitle: "Then return to BeeClean", index: 2)
        }
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(BeePalette.surface)
                .shadow(color: Color.black.opacity(0.04), radius: 10, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BeePalette.stroke, lineWidth: 1)
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(BeePalette.divider)
            .frame(height: 1)
            .padding(.leading, 70)
    }

    private func stepRow(number: String, title: String, subtitle: String, index: Int) -> some View {
        HStack(spacing: 14) {
            // Numbered circle in slate — clean checklist style.
            ZStack {
                Circle()
                    .fill(BeePalette.tileFill)
                    .overlay(
                        Circle().stroke(BeePalette.tileStroke, lineWidth: 1)
                    )
                    .frame(width: 36, height: 36)
                Text(number)
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundColor(BeePalette.ink)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundColor(BeePalette.ink)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(BeePalette.inkSoft)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -8)
        .animation(.easeOut(duration: 0.45).delay(0.18 + Double(index) * 0.06), value: appeared)
    }

    // MARK: Open Settings CTA — clean black button, no honey glow
    private var openSettingsButton: some View {
        Button {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gear")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.white)

                Text("Open iOS Settings")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(BeePalette.ink)
                    .shadow(color: Color.black.opacity(0.18), radius: 14, y: 8)
            )
        }
        .buttonStyle(ContactTileButtonStyle())
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.32), value: appeared)
    }

    // MARK: Fineprint
    private var fineprint: some View {
        Text("BeeClean works entirely on your device. Your contacts are never uploaded.")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(BeePalette.inkSoft)
            .multilineTextAlignment(.center)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.45).delay(0.40), value: appeared)
    }
}
