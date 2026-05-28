import SwiftUI
import Photos

// MARK: - AI Results Grid View
struct AIResultsGridView: View {
    let action: AIAction
    @State private var assetIds: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showExpanded = false
    @Environment(\.dismiss) private var dismiss

    // If the result set is larger than this, show a curated preview with a
    // "See all" drill-in instead of dumping everything on the first screen.
    private let previewThreshold = 12
    private let previewCount = 9

    var body: some View {
        ZStack {
            BitepalCanvas()

            VStack(spacing: 0) {
                resultsHeader
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if assetIds.isEmpty {
                    emptyView
                } else if assetIds.count > previewThreshold {
                    previewLayout
                } else {
                    AIResultsFullGrid(assetIds: $assetIds)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarHidden(true)
        .task { await loadResults() }
        .fullScreenCover(isPresented: $showExpanded) {
            AIResultsExpandedView(
                title: action.type.displayName,
                assetIds: $assetIds
            )
        }
    }

    // MARK: - Preview Layout (large result sets)
    private var previewLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summaryChip
                previewHero
                seeAllCTA
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }

    private var summaryChip: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text("Top \(min(previewCount, assetIds.count)) of \(assetIds.count) strongest matches")
                .font(.bodySmall)
                .fontWeight(.semibold)
        }
        .foregroundColor(.primaryColor)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule().fill(Color.primaryColor.opacity(0.12))
        )
    }

    private var previewHero: some View {
        let spacing: CGFloat = 6
        return LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: spacing),
                GridItem(.flexible(), spacing: spacing),
                GridItem(.flexible(), spacing: spacing),
            ],
            spacing: spacing
        ) {
            ForEach(Array(assetIds.prefix(previewCount)), id: \.self) { assetId in
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(
                        PhotoThumbnailView(
                            assetIdentifier: assetId,
                            size: CGSize(width: 300, height: 300)
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                    .onTapGesture {
                        // Click + 18ms echo — the second beat lands as
                        // the expanded grid pushes in, so the haptic
                        // reads as cause→effect, not just a single tap.
                        HapticManager.shared.tapSensation()
                        showExpanded = true
                    }
            }
        }
    }

    private var seeAllCTA: some View {
        Button {
            // Same primitive as the cell-tap-to-open path so both
            // ways of entering the expanded grid feel identical.
            HapticManager.shared.tapSensation()
            showExpanded = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primaryColor.opacity(0.15))
                        .frame(width: 46, height: 46)
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.primaryColor)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("See all \(assetIds.count) photos")
                        .font(.labelMedium)
                        .foregroundColor(.foreground)
                    Text("Browse the full related collection")
                        .font(.bodySmall)
                        .foregroundColor(.foregroundSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.foregroundSecondary)
            }
            .padding(16)
            .background(Color.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadowSm()
        }
        .buttonStyle(ScaleButtonStyle())
    }

    // MARK: - Loading
    private var loadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().scaleEffect(1.2)
            Text(action.type == .findByContent ? "Analyzing your photos…" : "Searching…")
                .font(.bodyMedium)
                .foregroundColor(.mutedForeground)
            if action.type == .findByContent {
                Text("This may take a moment")
                    .font(.bodySmall)
                    .foregroundColor(.mutedForeground.opacity(0.7))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Empty
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: action.type.iconName)
                .font(.system(size: 40, weight: .medium))
                .foregroundColor(.mutedForeground.opacity(0.5))
            if action.type == .findByContent {
                Text("No clear matches found")
                    .font(.bodyMedium)
                    .foregroundColor(.mutedForeground)
                Text("We only show photos that strongly match your search. Try rephrasing with a more specific or simpler term.")
                    .font(.bodySmall)
                    .foregroundColor(.mutedForeground.opacity(0.7))
                    .multilineTextAlignment(.center)
            } else {
                Text("No results found")
                    .font(.bodyMedium)
                    .foregroundColor(.mutedForeground)
                Text("Try a different search or adjust the filters.")
                    .font(.bodySmall)
                    .foregroundColor(.mutedForeground.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Error
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40, weight: .medium))
                .foregroundColor(.mutedForeground.opacity(0.5))
            Text(message)
                .font(.bodyMedium)
                .foregroundColor(.mutedForeground)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await loadResults() } }
                .font(.labelMedium)
                .foregroundColor(Color(hex: "3B82F6"))
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
    }

    // MARK: - Header
    private var resultsHeader: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.foreground)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(Color.white)
                    )
            }

            Spacer()

            Text(action.type.displayName)
                .font(.system(size: 19, weight: .heavy))
                .foregroundColor(.foreground)
                .tracking(-0.3)

            Spacer()

            Color.clear.frame(width: 38, height: 38)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    // MARK: - Data
    private func loadResults() async {
        isLoading = true
        errorMessage = nil

        do {
            let ids = try await AIService.shared.executeAction(action)
            assetIds = ids
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Expanded View (fullScreenCover destination)
struct AIResultsExpandedView: View {
    let title: String
    @Binding var assetIds: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BitepalCanvas()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.foreground)
                            .frame(width: 38, height: 38)
                            .background(
                                Circle()
                                    .fill(Color.white)
                            )
                    }

                    Spacer()

                    Text("All \(assetIds.count) results")
                        .font(.system(size: 19, weight: .heavy))
                        .foregroundColor(.foreground)
                        .tracking(-0.3)

                    Spacer()

                    Color.clear.frame(width: 38, height: 38)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)

                AIResultsFullGrid(assetIds: $assetIds)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarHidden(true)
    }
}

// MARK: - Reusable Full Grid with Selection + Delete
struct AIResultsFullGrid: View {
    @Binding var assetIds: [String]

    @State private var selectedIds: Set<String> = []
    @State private var isDeleting = false
    @State private var showDeleteConfirm = false

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    private var isSelecting: Bool { !selectedIds.isEmpty }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            gridScroll
            if isSelecting {
                deleteBar
            }
        }
        .alert("Delete \(selectedIds.count) items?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await performDelete() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("These items will be moved to Recently Deleted in Photos.")
        }
        // Warning notify the instant the destructive alert appears —
        // matches the destructive-confirm pattern used elsewhere in
        // the app (SavedFinds bulk-remove, Email cleanup). Pairs the
        // visual prompt with a tactile "are you sure" cue.
        .onChange(of: showDeleteConfirm) { _, isShown in
            if isShown { HapticManager.shared.destructiveConfirm() }
        }
    }

    private var headerBar: some View {
        HStack {
            Text("\(assetIds.count) results")
                .font(.bodySmall)
                .foregroundColor(.mutedForeground)

            Spacer()

            if isSelecting {
                Button("Deselect All") {
                    HapticManager.shared.filterChange()
                    selectedIds.removeAll()
                }
                .font(.bodySmall)
                .foregroundColor(Color(hex: "3B82F6"))
            } else {
                Button("Select All") {
                    HapticManager.shared.filterChange()
                    selectedIds = Set(assetIds)
                }
                .font(.bodySmall)
                .foregroundColor(Color(hex: "3B82F6"))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var gridScroll: some View {
        GeometryReader { geo in
            let cellSize = (geo.size.width - 24) / 3
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(assetIds, id: \.self) { assetId in
                        gridCell(assetId: assetId, cellSize: cellSize)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.bottom, isSelecting ? 80 : 100)
            }
        }
    }

    private func gridCell(assetId: String, cellSize: CGFloat) -> some View {
        let isSelected = selectedIds.contains(assetId)

        return Button {
            // Rotor-style selection tick per toggle — matches the iOS
            // picker / segmented-control feel users expect for a
            // multi-select grid. Fires inside the action so the haptic
            // lines up with the visual checkmark swap.
            HapticManager.shared.selection()
            toggleSelection(assetId)
        } label: {
            ZStack(alignment: .topLeading) {
                PhotoThumbnailView(
                    assetIdentifier: assetId,
                    size: CGSize(width: cellSize, height: cellSize)
                )
                .frame(width: cellSize, height: cellSize)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                if isSelected {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.black.opacity(0.35))
                        .frame(width: cellSize, height: cellSize)
                }

                ZStack {
                    Circle()
                        .fill(isSelected ? Color.destructive : Color.black.opacity(0.4))
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    } else {
                        Circle()
                            .stroke(Color.white.opacity(0.6), lineWidth: 2)
                            .frame(width: 20, height: 20)
                    }
                }
                .padding(6)
            }
        }
        .buttonStyle(.plain)
    }

    private var deleteBar: some View {
        VStack(spacing: 0) {
            Divider().background(Color.border)

            Button {
                // Heavy primary-commit feel — destructive intent
                // should land with weight. The confirm alert's own
                // destructiveConfirm warning notify fires next via
                // the .onChange above, so the user feels TWO beats:
                // commit + warning.
                HapticManager.shared.primaryCommit()
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 8) {
                    if isDeleting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "trash")
                    }
                    Text(isDeleting ? "Deleting…" : "Delete \(selectedIds.count) items")
                }
                .font(.labelMedium)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.destructive)
                .cornerRadius(12)
            }
            .disabled(isDeleting)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white)
        }
    }

    private func toggleSelection(_ assetId: String) {
        if selectedIds.contains(assetId) {
            selectedIds.remove(assetId)
        } else {
            selectedIds.insert(assetId)
        }
    }

    private func performDelete() async {
        isDeleting = true
        let idsToDelete = Array(selectedIds)
        let chunkSize = 200

        let chunks = stride(from: 0, to: idsToDelete.count, by: chunkSize).map { start in
            Array(idsToDelete[start..<min(start + chunkSize, idsToDelete.count)])
        }

        var deleted = Set<String>()

        for chunk in chunks {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: chunk, options: nil)
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetChangeRequest.deleteAssets(fetchResult as NSFastEnumeration)
                }
                deleted.formUnion(chunk)
            } catch {
                print("[AIResults] Delete chunk failed: \(error.localizedDescription)")
            }
        }

        assetIds.removeAll { deleted.contains($0) }
        selectedIds.subtract(deleted)
        isDeleting = false
        // Tactile resolution to the destructive flow — pairs with the
        // primaryCommit fired when the user tapped Delete and the
        // warning notify when the confirm alert appeared. Three beats
        // total: commit → warn → resolve.
        if !deleted.isEmpty {
            HapticManager.shared.actionSuccess()
        }
    }
}
