import SwiftUI

extension MediaGridView {
    // MARK: - Header (photo categories — Screenshots / Blurred / Other)
    //
    // Two-row layout, mirrors the Cleanup-class reference the user pulled in:
    //   Row 1: back chevron / Select All pill (left) + Select or Cancel (right)
    //   Row 2: large title (left) + Newest sort pill (right)
    //   Row 3: "N photos" subtitle
    //
    // The chrome is identical to `collapsingStyleHeader` used by video
    // categories — same back glyph, same title weight, same sort pill — but
    // the right-side action is an explicit Select/Cancel toggle instead of
    // the always-on Select All pill. Tapping Select flips `isSelecting` on
    // and a Select All pill swaps in on the left so the user can grab the
    // whole list in one tap.

    var header: some View {
        VStack(spacing: 0) {
            // Row 1: back / Select All on the left, Select / Cancel on the right.
            HStack(spacing: 10) {
                if isSelecting {
                    let allSelected = !items.isEmpty && selectedIds.count == items.count
                    TopBarSelectAllPill(isAllSelected: allSelected) {
                        toggleSelectAll()
                    }
                } else {
                    Button {
                        BottomNavBarVisibility.shared.releaseHide()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.foreground)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(Color.surfaceLight)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.border.opacity(0.5), lineWidth: 0.5)
                                    )
                            )
                    }
                }

                Spacer(minLength: 0)

                if !items.isEmpty {
                    Button {
                        if isSelecting {
                            // Cancel — drop selection and exit select mode.
                            isSelecting = false
                            selectedIds.removeAll()
                        } else {
                            isSelecting = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: isSelecting ? "xmark.circle.fill" : "checkmark.circle")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(
                                    isSelecting
                                        ? Color(hex: "1C1917")
                                        : Color(hex: "1C1917").opacity(0.55)
                                )
                                .symbolRenderingMode(.hierarchical)

                            Text(isSelecting ? "Cancel" : "Select")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(Color(hex: "1C1917"))
                                .tracking(-0.1)
                                .contentTransition(.opacity)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            ZStack {
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white, Color(hex: "F7F7F9")],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )

                                if isSelecting {
                                    // "Cancel" mode reads as a destructive
                                    // toggle — ink fill at low opacity tints
                                    // the pill without going full color.
                                    Capsule()
                                        .fill(Color(hex: "1C1917").opacity(0.06))
                                }
                            }
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    Color(hex: "1C1917").opacity(isSelecting ? 0.16 : 0.10),
                                    lineWidth: 0.75
                                )
                        )
                        .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
                        .animation(.easeOut(duration: 0.18), value: isSelecting)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 44)
            .padding(.bottom, 14)

            // Row 2: large title + sort filter pill. The pill aligns to the
            // title's text baseline so the two read as one row instead of
            // stacking the Newest pill directly under the top-row Select
            // pill (which made the right rail look cramped).
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(config.title)
                        .font(.custom("Poppins-Bold", size: 32))
                        .foregroundColor(Color(hex: "1C1917"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(collapsingHeaderSubtitle)
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !items.isEmpty {
                    SimilarSortPill(sortOption: sortOption) {
                        showFilters = true
                    }
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 6 }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    // MARK: - Selection Controls

    @ViewBuilder
    var selectionControls: some View {
        if isSelecting {
            // Just the running count. The Select All / Deselect All pill
            // moved to the top-right header when we unified the chrome,
            // and rendering it here too made every flat category look
            // like it had two competing primary actions stacked on top
            // of each other. Top-bar pill stays canonical.
            HStack {
                Text("\(selectedIds.count) selected")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.mutedForeground)

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Collapsing-Style Header (video categories)
    //
    // Matches the Similar Videos / Duplicates / Screenshots review screen
    // chrome: back + Deselect All on the compact top row, big category
    // title with the sort filter on the second row, count + selected as a
    // subtitle below. Video categories (Screen Recordings, Short, Long)
    // render this instead of the standard `header` because they don't have
    // swipe-mode and their cleanup UX matches the grouped review screens.

    var collapsingStyleHeader: some View {
        VStack(spacing: 0) {
            // Compact top bar — back + Select/Deselect All pill.
            HStack(spacing: 10) {
                Button {
                    BottomNavBarVisibility.shared.releaseHide()
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(Color(hex: "1C1917"))
                }

                Spacer(minLength: 0)

                if !items.isEmpty {
                    TopBarSelectAllPill(
                        isAllSelected: !items.isEmpty && selectedIds.count == items.count
                    ) {
                        toggleSelectAll()
                    }
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 36)
            .padding(.bottom, 14)

            // Large title row — title + count/selected subtitle on the left,
            // sort filter pill aligned to the title baseline on the right.
            // `.firstTextBaseline` keeps the Newest pill from stacking
            // directly under the top-row Select/Deselect pill.
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(config.title)
                        .font(.custom("Poppins-Bold", size: 32))
                        .foregroundColor(Color(hex: "1C1917"))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    Text(collapsingHeaderSubtitle)
                        .font(.custom("Poppins-Regular", size: 15))
                        .foregroundColor(Color(hex: "A1A1AA"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if !items.isEmpty {
                    SimilarSortPill(sortOption: sortOption) {
                        showFilters = true
                    }
                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 6 }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            // Hairline separator to anchor the title against the scrolling
            // grid below, matching the rest of the app's review-screen chrome.
            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 0.5)
        }
    }

    var collapsingHeaderSubtitle: String {
        let count = items.count
        let label = config.countLabel.lowercased()
        if !selectedIds.isEmpty {
            return "\(count) \(label) • \(selectedIds.count) selected"
        }
        return "\(count) \(label)"
    }

    func toggleSelectAll() {
        let allSelected = !items.isEmpty && selectedIds.count == items.count
        if allSelected {
            selectedIds.removeAll()
            isSelecting = false
        } else {
            selectedIds = Set(items.map(\.assetId))
            isSelecting = true
        }
    }

    // MARK: - Delete Progress Bar

    var deleteProgressBar: some View {
        VStack(spacing: 8) {
            ProgressView(value: store.deleteProgress.fraction)
                .progressViewStyle(LinearProgressViewStyle(tint: .destructive))

            HStack {
                Text("Deleting… \(store.deleteProgress.deleted)/\(store.deleteProgress.totalToDelete)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)

                Spacer()
            }
        }
        .padding(16)
        .background(Color.surfaceLight)
    }

    // MARK: - Delete Action

    func performDelete() async {
        let ids = Array(selectedIds)
        // Reuse the same `sourceCategory` already plumbed through
        // `config.saveContext` for the SaveFindButton — same leaf
        // identity, same enum, so the Progress chart timeline chip
        // row can filter by it without any new wiring upstream.
        let success = await store.deleteFlatAssets(
            assetIds: ids,
            category: config.saveContext?.sourceCategory
        ) {
            await config.refreshAfterDelete(store, Set(ids))
        }
        if success {
            selectedIds.removeAll()
            // Leave `isSelecting` on so the user can keep cleaning — they hit
            // Done when they're finished. Matches CleanerGuru / AI Cleaner.
        } else {
            showErrorAlert = true
        }
    }

}
