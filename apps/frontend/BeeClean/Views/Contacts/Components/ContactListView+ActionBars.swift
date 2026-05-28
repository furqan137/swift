import SwiftUI
import Contacts

extension ContactListView {

    // MARK: - Merge Preview Bar
    //
    // Sticky vivid-blue capsule CTA that mirrors the Cleanup reference:
    // appears the moment the user checkmarks any duplicate, hides when the
    // selection is cleared. Tapping it opens MergePreviewView, which lets
    // the user see exactly what the merged result will look like before
    // committing — the destructive merge is gated behind one more confirm
    // dialog + an optional backup prompt inside that sheet.
    /// Wraps the pinned bottom CTA in a backdrop strip so the scroll
    /// content underneath doesn't visibly bleed past the button. Top
    /// edge fades from transparent → canvas-tinted opaque so the
    /// transition between the scroll list and the CTA strip reads as
    /// a soft horizon rather than a hard cut. Bottom is solid Bitepal
    /// canvas color extending into the home-indicator zone so the
    /// home-indicator background stays consistent with the rest of
    /// the app.
    @ViewBuilder
    func bottomCTABackdrop<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            // Soft fade strip — 28pt of vertical fade-out so cards
            // dissolve into the canvas instead of being hard-clipped
            // by the CTA strip's leading edge.
            LinearGradient(
                colors: [
                    Color(hex: "E3E6EE").opacity(0),
                    Color(hex: "E3E6EE").opacity(1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 28)

            // Solid backdrop the CTA actually sits on. Tinted to the
            // Bitepal canvas's mid stop so the strip and the canvas
            // read as the same surface family, just the strip is
            // opaque and the canvas above is semi-transparent.
            content()
                .frame(maxWidth: .infinity)
                .background(Color(hex: "E3E6EE"))
        }
    }

    var mergePreviewBar: some View {
        Button {
            HapticManager.shared.impact(.medium)
            if SubscriptionService.shared.isPro {
                showMergePreview = true
            } else {
                featureGateAction = .merge
                showFeatureGate = true
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 16, weight: .semibold))
                Text("See Merge Preview")
                    .font(.system(size: 17, weight: .bold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                ZStack {
                    // Bitepal espresso fill — matches the Merge CTA
                    // inside MergePreviewView and the segmented
                    // control's active pill so all primary CTAs
                    // share one fill language across the app.
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "2A2724"),
                                    Color(hex: "0F0E0C")
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Top rim-light highlight — same plusLighter trick
                    // the BottomNavBar uses. Single most effective
                    // "premium hardware" cue at button scale; turns
                    // the flat ink fill into a lit-from-above pill.
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.22),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 0.8
                        )
                        .blendMode(.plusLighter)
                }
            )
            // Stacked shadows mirror the BottomNavBar / FAB signature
            // so the CTA sits on the same elevation plane as those
            // surfaces — visibly floats off the canvas without
            // looking heavy.
            .shadow(color: Color.black.opacity(0.22), radius: 4, y: 2)
            .shadow(color: Color.black.opacity(0.18), radius: 22, y: 10)
        }
        .buttonStyle(ScaleButtonStyle())
        .padding(.horizontal, 20)
        // Was 14pt — the parent's `.ignoresSafeArea(.container,
        // edges: .bottom)` ate that into the home-indicator zone,
        // leaving the button visibly smushed against the screen edge
        // with no breathing room. 38pt clears the home indicator on
        // every iPhone with a notch + leaves a real gap so the CTA
        // reads as a button, not a banner.
        .padding(.bottom, 38)
    }

    // MARK: - Primary Delete CTA
    //
    // Single full-width button replacing the old cramped action bar.
    // Visual language is lifted from the photo cleanup's pinned delete
    // bar — bold blue background, trash icon + "Delete X items" label,
    // centred, with a soft glow shadow.
    //
    // Copy adapts per category:
    //   • Duplicates → "Delete X Duplicates"
    //   • Incomplete → "Delete X Contacts"
    //   • All        → "Delete X Contacts"
    var primaryDeleteCTA: some View {
        let count = selectedContacts.count
        let noun: String = {
            switch category {
            case .duplicates: return count == 1 ? "Duplicate" : "Duplicates"
            default:          return count == 1 ? "Contact"   : "Contacts"
            }
        }()

        return Button {
            HapticManager.shared.impact(.medium)
            if SubscriptionService.shared.isPro {
                showDeleteConfirm = true
            } else {
                featureGateAction = .delete
                showFeatureGate = true
            }
        } label: {
            HStack(spacing: 10) {
                if isDeleting {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.85)
                } else {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 16, weight: .semibold))
                }

                Text("Delete \(count) \(noun)")
                    .font(.system(size: 17, weight: .bold))
                    .contentTransition(.numericText(countsDown: false))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                Capsule().fill(Color(hex: "DC2626"))
            )
            .shadow(color: Color(hex: "DC2626").opacity(0.22), radius: 14, y: 6)
        }
        .buttonStyle(ScaleButtonStyle())
        .disabled(isDeleting)
    }

    // MARK: - Load More Footer
    var loadMoreFooter: some View {
        HStack(spacing: 10) {
            if isLoadingMore {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "1C1917")))
                    .scaleEffect(0.7)
            }
            Text("Loading more contacts...")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "9B9490"))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Loading
    var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "1C1917")))
                .scaleEffect(1.2)
            Text("Loading contacts...")
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "9B9490"))
            Spacer()
        }
    }

    // MARK: - Empty / Success State
    //
    // One canvas-filling illustration for every "all clean / nothing here"
    // state. No halos, no rings, no wiggle — the asset already carries the
    // brand voice (cartoon bee in a meadow holding a magnifying glass over
    // contacts). Trying to dress it with procedural overlays just made it
    // look small and squished, which is what the user kept rejecting.
    //
    // Title + subtitle stay below the image and adapt per category, but the
    // image is the same hero across Duplicates, Incomplete, All Contacts,
    // Backups, and search-empty. One image, one calm composition, premium.

    /// Tightened copy — single short sentence each so nothing truncates,
    /// reads as Apple-default empty-state voice rather than two-line filler.
    private var emptyStateCopy: (title: String, subtitle: String) {
        switch category {
        case .duplicates:
            return ("All Clean", "Your hive has no duplicate contacts.")
        case .incomplete:
            return ("All Complete", "Every contact is filled in.")
        case .backups:
            return ("No Backups Yet", "Create one to keep your hive safe.")
        case .all:
            if !searchText.isEmpty {
                return ("No Results", "No contacts match your search.")
            }
            return ("No Contacts", "This category is empty.")
        }
    }

    /// Empty-state hero. Vertically centered composition: the entire
    /// (image + title + subtitle) block lives inside two flexible Spacers
    /// so the empty area splits symmetrically above and below — no more
    /// dead white space dangling at the bottom of the page.
    ///
    ///   1. Edge-to-edge image at 56% of available height, `.scaledToFill`,
    ///      bottom-fade mask so the asset dissolves into the page bg with
    ///      no hard edge.
    ///   2. Anton-Regular headline pulled tight against the fade tail so
    ///      the image and title read as one block.
    ///   3. Single short subtitle below that.
    ///   4. A small ghost "Run scan again" button anchors the bottom — same
    ///      premium empty-state pattern used by Things / Linear / Bear.
    var emptyView: some View {
        GeometryReader { geo in
            let heroH = geo.size.height * 0.56
            let copy = emptyStateCopy

            VStack(spacing: 0) {
                Spacer(minLength: 8)

                Image("bee_contacts_clean")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: heroH)
                    .clipped()
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .black, location: 0.0),
                                .init(color: .black, location: 0.70),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                VStack(spacing: 10) {
                    Text(copy.title)
                        .font(.custom("Anton-Regular", size: 44))
                        .tracking(-0.5)
                        .foregroundColor(Color(hex: "1C1917"))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(copy.subtitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(hex: "78716C"))
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)
                .padding(.top, -20) // pull title up into the fade tail

                Spacer(minLength: 24)

                // Ghost CTA — anchors the bottom of the composition so
                // the page doesn't end in dead space. Light haptic on tap.
                if category == .duplicates || category == .incomplete {
                    Button {
                        HapticManager.shared.impact(.light)
                        Task { await viewModel.loadContacts() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 12, weight: .bold))
                            Text("Scan Again")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "78716C"))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color.white.opacity(0.7))
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                        )
                        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

}

