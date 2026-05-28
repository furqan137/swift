import SwiftUI

// MARK: - CompressView: Subviews + Helpers
extension CompressView {

    // MARK: - Resume Prompt
    //
    // Bitepal "Continue where you left off?" sheet — fades in over the
    // grid when the user has a saved scroll position past the threshold.
    // Tap "Let's Go" → set `pendingScrollCategory`, dismiss sheet,
    // ScrollViewReader's `.onChange` jumps the grid back to the index.
    @ViewBuilder
    var resumeOverlay: some View {
        if let prompted = resume.promptedCategory {
            ZStack(alignment: .bottom) {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { resume.dismissPrompt() }

                CompressResumeSheet(
                    category: prompted,
                    onResume: {
                        pendingScrollCategory = prompted
                        resume.dismissPrompt()
                    },
                    onDismiss: {
                        resume.clear(prompted)
                        resume.dismissPrompt()
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: resume.promptedCategory)
        }
    }

    func evaluateResumePrompt(for category: CompressCategory) {
        // Only consider once data is actually loaded — otherwise totalItems
        // is 0 and the manager skips the prompt.
        let total = (category == .videos) ? sortedVideos.count : sortedPhotos.count
        guard total > 0 else { return }
        resume.considerPrompt(for: category, totalItems: total)
    }

    // MARK: - Header
    var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            compressTopRow
            compressTitleBlock
        }
        .padding(.bottom, 14)
    }

    /// Top row — chevron on the left, filter pill on the right. Kept
    /// in its own computed property so SwiftUI's view-builder doesn't
    /// blow past its type-check budget when the entire header was one
    /// nested expression (was causing an EXC_BAD_ACCESS on tap-in).
    private var compressTopRow: some View {
        HStack(alignment: .center, spacing: 12) {
            if showsBackButton {
                Button {
                    HapticManager.shared.arrowNudge(.backward)
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color(hex: "1C1917"))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.white)
                                .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
                        )
                        .overlay(
                            Circle().stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                        )
                }
                .buttonStyle(ScaleButtonStyle())
            }

            Spacer()

            filterPillButton
        }
        .padding(.horizontal, 20)
    }

    private var filterPillButton: some View {
        Button {
            HapticManager.shared.impact(.light)
            showFilters = true
        } label: {
            let active = isFilterActive
            HStack(spacing: 7) {
                Image(systemName: "line.3.horizontal.decrease")
                    .font(.system(size: 11, weight: .heavy))
                Text(active ? sortOption.rawValue : "Filter")
                    .font(.custom("Poppins-Bold", size: 13))
                if active {
                    Circle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 4, height: 4)
                }
            }
            .foregroundColor(active ? .white : Color(hex: "1C1917"))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(filterPillBackground(active: active))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var compressTitleBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(BCLoc.compress.tr)
                .font(.custom("Poppins-Bold", size: 28))
                .foregroundColor(.foreground)

            Text(formatBytes(currentTotalSize))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.foregroundSecondary)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Filter Pill Helpers

    /// True when ANY sort is selected or a date range is applied —
    /// which is always-true for sort, so the pill consistently
    /// reflects the active sort name in the espresso-ink active style.
    /// Previous version excluded `.largest` (treated as the default),
    /// which left the pill stuck on the gray "Filter" label whenever
    /// the user picked Largest. Users expect the pill to mirror their
    /// most recent choice regardless of which option is the default.
    var isFilterActive: Bool {
        true
    }

    /// Chrome-glass capsule background for the filter pill. Active
    /// state uses the same espresso ink + top rim-light + ambient
    /// glow signature as the BottomNavBar's selected indicator, so
    /// the active pill reads as the same elevated chrome family.
    @ViewBuilder
    func filterPillBackground(active: Bool) -> some View {
        ZStack {
            if active {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hex: "2C2C2E"),
                                Color(hex: "0A0A0A")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
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
                Capsule()
                    .stroke(Color.black.opacity(0.18), lineWidth: 0.5)
            } else {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color(hex: "F8F9FB")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Capsule()
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.95),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: 0.8
                    )
                    .blendMode(.plusLighter)
                Capsule()
                    .stroke(Color.black.opacity(0.08), lineWidth: 0.5)
            }
        }
        .compositingGroup()
        .shadow(
            color: active ? Color.black.opacity(0.22) : Color.black.opacity(0.06),
            radius: active ? 10 : 4,
            y: active ? 4 : 2
        )
    }

    // MARK: - Category Picker
    var categoryPicker: some View {
        // 0pt spacing + 0pt parent padding so the active dark half
        // fills its segment edge-to-edge with no white border. The
        // white half is just the parent capsule's fill showing
        // through, so the dark/white contrast IS the separator —
        // matches the iOS native segmented control reference.
        HStack(spacing: 0) {
            ForEach(CompressCategory.allCases) { cat in
                Button {
                    HapticManager.shared.impact(.light)
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                        category = cat
                    }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 14, weight: .bold))
                        Text(cat.rawValue)
                            .font(.custom("Poppins-Bold", size: 17))
                    }
                    .foregroundColor(category == cat ? .white : Color(hex: "57534E"))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        ZStack {
                            if category == cat {
                                // No horizontal inset — the active dark
                                // capsule fills its half edge-to-edge.
                                // Matches the iOS-native segmented look
                                // the user referenced: the dark fill on
                                // one half is its own separator from the
                                // white half on the other side, so the
                                // explicit divider line we used to draw
                                // here just added visual noise. Shadow
                                // kept tight so it doesn't smudge into
                                // the inactive half.
                                Capsule()
                                    .fill(Color(hex: "1C1917"))
                                    .matchedGeometryEffect(id: "categoryBg", in: categoryNamespace)
                                    .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        // No internal padding — segments fill the parent capsule edge-
        // to-edge. The clipShape is what keeps the active dark half's
        // outer corner rounded to match the parent capsule's curve.
        .background(Capsule().fill(Color.white))
        .clipShape(Capsule())
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    // MARK: - Savings Banner
    //
    // Bitepal-pure: flat white card on the cool gradient, NO shadow,
    // NO border. Poppins typography to match the section headers.
    var savingsBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.right.and.arrow.up.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color(hex: "1C1917"))

            Text(category == .videos
                 ? "Compress your videos and save storage up to"
                 : "Compress your photos and save storage up to")
                .font(.custom("Poppins-Regular", size: 14))
                .foregroundColor(Color(hex: "8A8A8E"))
                .lineLimit(2)

            Spacer(minLength: 0)

            Text(formatBytes(hasDateFilter ? currentFilteredSavings : currentPotentialSavings))
                .font(.custom("Poppins-Bold", size: 22))
                .foregroundColor(Color(hex: "1C1917"))
                .fixedSize(horizontal: true, vertical: false)
                .contentTransition(.numericText())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
        )
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: - Filter Indicator
    var filterIndicatorInline: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "1C1917"))

            Text("\(currentDisplayCount) of \(currentSourceCount) \(category.rawValue.lowercased())")
                .font(.custom("Poppins-Bold", size: 12))
                .foregroundColor(Color(hex: "A1A1AA"))

            Spacer()

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    startDate = nil
                    endDate = nil
                }
            } label: {
                HStack(spacing: 3) {
                    Text("Clear")
                        .font(.system(size: 11, weight: .semibold))
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundColor(Color(hex: "1C1917"))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(hex: "1C1917").opacity(0.08))
                .cornerRadius(6)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Content Grid
    //
    // 12-pt spacing on both axes — wide enough that the redesigned big-pill
    // cards feel like they have room to breathe (mirrors the reference 2-col
    // pattern), tight enough that two cards still fit comfortably across a
    // standard iPhone width.
    var contentGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ], spacing: 12) {
            // ForEach identity must be the asset's stable id, NOT the index.
            //
            // The previous build used `ForEach(arr.indices, id: \.self)` to
            // skip the `Array(.enumerated())` tuple allocation, but
            // `sortedPhotos` / `sortedVideos` are sortable — when the user
            // flips Largest → Newest the ARRAY reorders while indices stay
            // 0…N, so SwiftUI matched identity by position and reassigned
            // each existing cell a new asset. That blew away every
            // `PhotoCompressCard`'s thumbnail cache + `@State thumbnail`
            // and refired `PHImageManager.requestImage` for every visible
            // tile on every sort change. With a 4500-photo library the
            // post-sort tile flicker was the dominant lag source.
            //
            // `id: \.element.id` matches identity on the asset's
            // `localIdentifier`, so a sort permutation just swaps cell
            // POSITIONS in the lazy grid — the cell instances and their
            // thumbnails travel with the photo they represent. The
            // `Array(.enumerated())` allocation is O(n) once per body
            // render against an n-cell layout pass that is itself O(n+),
            // so the alloc disappears in the noise and the explicit
            // `.id("v-…")` / `.id("p-…")` per-cell namespacing prevents
            // photo/video state cross-contamination across category
            // toggles.
            if category == .videos {
                ForEach(Array(sortedVideos.enumerated()), id: \.element.id) { index, video in
                    VideoCompressCard(video: video)
                        .id("v-\(video.id)")
                        .onAppear { resume.recordSeen(index, for: .videos) }
                }
            } else {
                ForEach(Array(sortedPhotos.enumerated()), id: \.element.id) { index, photo in
                    PhotoCompressCard(photo: photo)
                        .id("p-\(photo.id)")
                        .onAppear { resume.recordSeen(index, for: .photos) }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 100)
    }


    // MARK: - No Match View
    var noMatchView: some View {
        VStack(spacing: 16) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundColor(Color(hex: "A1A1AA").opacity(0.5))

            VStack(spacing: 4) {
                Text(category == .videos ? "No videos match" : "No photos match")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
                Text("Try a different date range")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "A1A1AA"))
            }

            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    startDate = nil
                    endDate = nil
                }
            } label: {
                Text("Clear Filters")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1917"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(hex: "1C1917").opacity(0.08))
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - Reload current
    func reloadCurrent() async {
        if category == .videos {
            await vm.reloadVideos()
        } else {
            await vm.reloadPhotos()
        }
    }
}

#Preview {
    CompressView()
        .preferredColorScheme(.light)
}
