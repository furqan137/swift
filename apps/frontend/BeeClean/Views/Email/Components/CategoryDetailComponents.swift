import SwiftUI

// MARK: - Category Detail Header
struct CategoryDetailHeader: View {
    let categoryName: String
    let categoryIcon: String
    var categoryColor: Color = Color(hex: "1C1917")
    let hasActiveFilters: Bool
    let onBack: () -> Void
    let onFilter: () -> Void
    var onRefresh: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            Button(action: {
                HapticManager.shared.arrowNudge(.backward)
                onBack()
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .frame(width: 32, height: 32)
                    .background(Color(hex: "F5F5F4"))
                    .clipShape(Circle())
            }

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    categoryColor,
                                    categoryColor.opacity(0.82)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 30, height: 30)
                        .shadow(color: categoryColor.opacity(0.35), radius: 6, y: 2)

                    Image(systemName: categoryIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                }

                Text(categoryName)
                    // Poppins-Bold matches the BitePal header type used by
                    // every other category title in the app (ContactList,
                    // MergePreview, etc.) so the email category headers
                    // belong to the same family.
                    .font(.custom("Poppins-Bold", size: 19))
                    .foregroundColor(Color(hex: "1C1917"))
            }

            Spacer()

            // Refresh button
            if let onRefresh {
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .frame(width: 32, height: 32)
                        .background(Color(hex: "1C1917").opacity(0.06))
                        .clipShape(Circle())
                }
            }

            // Filter button — Bitepal lavender pill at rest, solid ink
            // capsule when any filter is active. Solid black reads as
            // confident and decisive on the cool-grey Bitepal canvas.
            Button(action: onFilter) {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 13, weight: .bold))
                    Text(BCLoc.filters.tr)
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(hasActiveFilters ? .white : Color(hex: "1C1917"))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    Capsule().fill(hasActiveFilters ? Color(hex: "0A0A0A") : Color(hex: "EEEDF3"))
                )
                .shadow(
                    color: hasActiveFilters ? Color.black.opacity(0.22) : .clear,
                    radius: 10, y: 4
                )
                .animation(.easeOut(duration: 0.22), value: hasActiveFilters)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

// MARK: - Category Detail Search Bar (no All button)
struct CategoryDetailSearchBar: View {
    @Binding var searchText: String
    let messagesEmpty: Bool
    let visibleCount: Int
    let totalLoaded: Int
    // Keep params for backwards compat but ignore them
    var onSelectAll: (() -> Void)? = nil
    var allSelected: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundColor(.gray.opacity(0.6))

            TextField("Search emails...", text: $searchText)
                .font(.system(size: 14))
                .foregroundColor(Color(hex: "1C1917"))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { searchText = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.gray.opacity(0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: "F5F5F4"))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Active Filter Chip
struct ActiveFilterChip: View {
    let text: String
    let icon: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(Color.orange.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .foregroundColor(.orange)
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(maxWidth: 200)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Category Detail Delete Bar
//
// BitePal-polished floating action bar. Replaces the previous
// flat-red button + detached counter circle + dismiss X with one
// cohesive pill: counter chip + primary delete capsule + dismiss
// chip, all on a soft frosted-white pill that uses the same
// lighting model as the segmented control / nav bar.
struct CategoryDetailDeleteBar: View {
    let selectedCount: Int
    let isDeleting: Bool
    let onDelete: () -> Void
    let onDeselect: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Counter chip — espresso ink, white digit. Reads as "this
            // many will go" before the eye even reaches the action.
            Text("\(selectedCount)")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .frame(minWidth: 36, minHeight: 36)
                .padding(.horizontal, 8)
                .background(
                    Capsule()
                        .fill(Color(hex: "1C1917"))
                )
                .contentTransition(.numericText(countsDown: false))

            // Primary action — deep BitePal red (`#DC2626`) capsule with
            // tight rim-light + soft shadow, matching the active-tab
            // indicator on the nav bar in lighting model.
            Button(action: onDelete) {
                HStack(spacing: 8) {
                    if isDeleting {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(isDeleting ? "Deleting…" : "Delete Selected")
                        .font(.custom("Poppins-Bold", size: 15))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "EF4444"), Color(hex: "DC2626")],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.40),
                                            Color.white.opacity(0)
                                        ],
                                        startPoint: .top,
                                        endPoint: .center
                                    ),
                                    lineWidth: 0.8
                                )
                                .blendMode(.plusLighter)
                        )
                        .overlay(
                            Capsule()
                                .stroke(Color.black.opacity(0.10), lineWidth: 0.5)
                        )
                        .shadow(color: Color(hex: "DC2626").opacity(0.35), radius: 8, x: 0, y: 4)
                )
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
            .opacity(isDeleting ? 0.7 : 1)

            // Dismiss chip — faded ghost X. Users intuitively know to
            // tap it to clear the selection (or just tap a row to
            // deselect), so the chip steps back visually instead of
            // competing with the primary Delete CTA. No background fill,
            // no border — just a low-opacity glyph in the floating pill.
            Button(action: onDeselect) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "57534E").opacity(0.45))
                    .frame(width: 32, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isDeleting)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            // Floating BitePal pill — `F1F1F3 → E8E8EB` warm-gray ground
            // with the same rim-light + bevel + hairline + stacked shadows
            // as the bottom nav bar. The bar reads as a sibling of the
            // nav, not a foreign red box bolted onto the bottom.
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "F1F1F3"), Color(hex: "E8E8EB")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.92),
                                    Color.white.opacity(0)
                                ],
                                startPoint: .top,
                                endPoint: .center
                            ),
                            lineWidth: 0.8
                        )
                        .blendMode(.plusLighter)
                )
                .overlay(
                    Capsule()
                        .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
                .shadow(color: Color.black.opacity(0.12), radius: 18, x: 0, y: 8)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
    }
}

// MARK: - Live Counter Text
struct LiveCounterText: View {
    let hasActiveFilters: Bool
    let searchText: String
    let visibleCount: Int
    let loadedCount: Int
    let totalEstimate: Int
    let hasNextPage: Bool
    /// True while the backend's wave-based scan is filling the cache.
    /// Surfaces a subtle "· Scanning…" suffix so the user sees the list
    /// is live, mirroring the unsubscribe scan progress affordance.
    var isScanning: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            counterText
            // Pulse badge for any "more data on the way" signal: backend
            // wave scan filling the cache, OR pagination still draining
            // pages. Without the pagination branch, filtered queries
            // could sit on a stale-looking "201 FILTERED EMAILS" with no
            // visible indication that more rows are still arriving.
            if isScanning || hasNextPage {
                ScanningPulseBadge(label: hasNextPage && !isScanning ? "Loading more…" : "Scanning…")
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isScanning)
        .animation(.easeInOut(duration: 0.2), value: hasNextPage)
    }

    @ViewBuilder
    private var counterText: some View {
        // Sleeker subtitle: Poppins-SemiBold 11pt with subtle uppercase
        // tracking. Reads as a refined, editorial caption beside the
        // category title — not the chunky bold subtitle it was before.
        //
        // Pagination honesty: when `hasNextPage` is true we APPEND a "+"
        // to the number so the user never reads it as the final total.
        // Gmail's `resultSizeEstimate` underreports filtered queries
        // (notoriously stuck at 201) — without the "+" the user assumes
        // the filter is capped at whatever number is currently showing.
        // The "+" plus the scanning pulse below it makes clear that more
        // is still arriving.
        let totalForDisplay = max(loadedCount, totalEstimate)
        let suffix = hasNextPage ? "+" : ""

        if hasActiveFilters {
            if !searchText.isEmpty {
                tracked("\(numFmt(visibleCount)) MATCHING · \(numFmt(totalForDisplay))\(suffix) FILTERED")
                    .foregroundColor(Color(hex: "C2410C"))
            } else {
                tracked("\(numFmt(totalForDisplay))\(suffix) FILTERED EMAILS")
                    .foregroundColor(Color(hex: "C2410C"))
            }
        } else if !searchText.isEmpty {
            tracked("\(numFmt(visibleCount)) MATCHING · \(numFmt(loadedCount)) OF \(numFmt(totalForDisplay))\(suffix)")
                .foregroundColor(Color(hex: "9A9590"))
        } else if totalForDisplay > 0 {
            tracked("\(numFmt(totalForDisplay))\(suffix) EMAILS")
                .foregroundColor(Color(hex: "9A9590"))
        } else {
            tracked("LOADING")
                .foregroundColor(Color(hex: "C7C2BC"))
        }
    }

    private func tracked(_ text: String) -> Text {
        Text(text)
            .font(.custom("Poppins-SemiBold", size: 11))
            .tracking(1.2)
    }

    private func numFmt(_ num: Int) -> String {
        EmailFormatters.numFmt(num)
    }
}

// MARK: - Scanning Pulse Badge
/// A small pulsing dot + "Scanning…" label shown when the backend is
/// progressively filling the cache. Same visual language as the
/// unsubscribe scan affordance.
struct ScanningPulseBadge: View {
    var label: String = "Scanning…"
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: "059669"))
                .frame(width: 6, height: 6)
                .opacity(pulse ? 0.35 : 1.0)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(hex: "059669"))
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Quick Clean CTA
struct QuickCleanCTA: View {
    let categoryName: String
    let emailCount: Int
    let onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    // Poppins-Bold matches the BitePal type system used by
                    // every other category title. The "Clean your X inbox"
                    // line is the most prominent CTA on the screen — it
                    // should belong to the same family as the headers.
                    Text("Clean your \(categoryName) inbox")
                        .font(.custom("Poppins-Bold", size: 15))
                        .foregroundColor(Color(hex: "1C1917"))

                    Text("\(EmailFormatters.numFmt(emailCount)) emails ready to review")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }

                Spacer()

                HStack(spacing: 4) {
                    Text("Start")
                        .font(.system(size: 13, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(hex: "1C1917"))
                .cornerRadius(8)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(hex: "F5F5F4"))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
