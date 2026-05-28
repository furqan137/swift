import SwiftUI
import Photos

// MARK: - PhotoKit Test View
/// Debug view to verify PhotoKit integration, dHash64, and sharpness scoring
struct PhotoKitTestView: View {
    @StateObject private var photoService = PhotoKitService.shared
    @State private var photoLimit = 100
    @State private var similarGroups: [[AnalyzedPhoto]] = []
    @State private var blurryPhotos: [AnalyzedPhoto] = []
    @State private var showResults = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Authorization Status
                    authorizationSection

                    // Analysis Controls
                    controlsSection

                    // Progress Section
                    if photoService.isAnalyzing {
                        progressSection
                    }

                    // Results Section
                    if showResults && !photoService.isAnalyzing {
                        resultsSection
                    }
                }
                .padding()
            }
            .navigationTitle("PhotoKit Test")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Authorization Section
    private var authorizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Authorization Status")
                .font(.headline)

            HStack {
                Circle()
                    .fill(authorizationColor)
                    .frame(width: 12, height: 12)

                Text(authorizationText)
                    .font(.subheadline)

                Spacer()

                if photoService.authorizationStatus != .authorized {
                    Button("Request Access") {
                        Task {
                            await photoService.requestAuthorization()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    private var authorizationColor: Color {
        switch photoService.authorizationStatus {
        case .authorized, .limited: return .green
        case .denied, .restricted: return .red
        case .notDetermined: return .orange
        @unknown default: return .gray
        }
    }

    private var authorizationText: String {
        switch photoService.authorizationStatus {
        case .authorized: return "Full Access Granted"
        case .limited: return "Limited Access"
        case .denied: return "Access Denied"
        case .restricted: return "Access Restricted"
        case .notDetermined: return "Not Determined"
        @unknown default: return "Unknown"
        }
    }

    // MARK: - Controls Section
    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analysis Controls")
                .font(.headline)

            VStack(spacing: 16) {
                // Photo limit picker
                HStack {
                    Text("Photo Limit:")
                    Picker("Limit", selection: $photoLimit) {
                        Text("100").tag(100)
                        Text("200").tag(200)
                        Text("300").tag(300)
                        Text("500").tag(500)
                    }
                    .pickerStyle(.segmented)
                }

                // Analyze button
                Button {
                    Task {
                        await analyzePhotos()
                    }
                } label: {
                    HStack {
                        if photoService.isAnalyzing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: "photo.stack")
                        }
                        Text(photoService.isAnalyzing ? "Analyzing..." : "Analyze Photos")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(photoService.isAnalyzing ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .disabled(photoService.isAnalyzing ||
                         (photoService.authorizationStatus != .authorized &&
                          photoService.authorizationStatus != .limited))

                // Cancel button
                if photoService.isAnalyzing {
                    Button("Cancel") {
                        photoService.cancelAnalysis()
                    }
                    .foregroundColor(.red)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Progress Section
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.headline)

            VStack(spacing: 12) {
                // Progress bar
                ProgressView(value: photoService.analysisProgress.progress)
                    .progressViewStyle(LinearProgressViewStyle())

                // Stats
                HStack {
                    VStack(alignment: .leading) {
                        Text(photoService.analysisProgress.currentPhase)
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("\(photoService.analysisProgress.processedPhotos) / \(photoService.analysisProgress.totalPhotos)")
                            .font(.title2)
                            .fontWeight(.bold)
                    }

                    Spacer()

                    Text("\(photoService.analysisProgress.percentComplete)%")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                }

                // Error if any
                if let error = photoService.analysisProgress.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }

    // MARK: - Results Section
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Summary
            summarySection

            // Sample Photos with Hash/Sharpness
            samplePhotosSection

            // Similar Photos
            if !similarGroups.isEmpty {
                similarPhotosSection
            }

            // Blurry Photos
            if !blurryPhotos.isEmpty {
                blurryPhotosSection
            }
        }
    }

    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Analysis Results")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatCard(title: "Total Analyzed", value: "\(photoService.analyzedPhotos.count)", color: .blue)
                StatCard(title: "Similar Groups", value: "\(similarGroups.count)", color: .orange)
                StatCard(title: "Blurry Photos", value: "\(blurryPhotos.count)", color: .red)
                StatCard(title: "Avg Sharpness", value: String(format: "%.0f", averageSharpness), color: .green)
            }
        }
    }

    private var averageSharpness: Double {
        guard !photoService.analyzedPhotos.isEmpty else { return 0 }
        let total = photoService.analyzedPhotos.reduce(0.0) { $0 + $1.sharpnessScore }
        return total / Double(photoService.analyzedPhotos.count)
    }

    private var samplePhotosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sample Photos (First 10)")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(photoService.analyzedPhotos.prefix(10)) { photo in
                        PhotoAnalysisCard(photo: photo)
                    }
                }
            }
        }
    }

    private var similarPhotosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Similar Photo Groups (\(similarGroups.count) groups)")
                .font(.headline)

            ForEach(Array(similarGroups.prefix(3).enumerated()), id: \.offset) { index, group in
                VStack(alignment: .leading, spacing: 8) {
                    Text("Group \(index + 1) - \(group.count) photos")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(group.prefix(5)) { photo in
                                PhotoThumbnailView(assetIdentifier: photo.assetIdentifier, size: CGSize(width: 80, height: 80))
                                    .frame(width: 80, height: 80)
                            }
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
    }

    private var blurryPhotosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Blurry Photos (\(blurryPhotos.count) found)")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(blurryPhotos.prefix(10)) { photo in
                        VStack(spacing: 4) {
                            PhotoThumbnailView(assetIdentifier: photo.assetIdentifier, size: CGSize(width: 80, height: 80))
                                .frame(width: 80, height: 80)
                            Text(String(format: "%.0f", photo.sharpnessScore))
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions
    private func analyzePhotos() async {
        showResults = false
        await photoService.analyzePhotos(limit: photoLimit)

        // Find similar and blurry photos
        similarGroups = photoService.findSimilarPhotos(threshold: 10)
        blurryPhotos = photoService.findBlurryPhotos(threshold: 100)
        showResults = true
    }
}

// MARK: - Supporting Views
struct StatCard: View {
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct PhotoAnalysisCard: View {
    let photo: AnalyzedPhoto
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 8) {
            // Thumbnail
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray4))
                    .frame(width: 100, height: 100)
                    .overlay(ProgressView())
            }

            // dHash
            VStack(spacing: 2) {
                Text("dHash")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%016llX", photo.dHash64))
                    .font(.system(size: 8, design: .monospaced))
                    .lineLimit(1)
            }

            // Sharpness
            VStack(spacing: 2) {
                Text("Sharpness")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(String(format: "%.0f", photo.sharpnessScore))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(sharpnessColor)
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .onAppear {
            loadThumbnail()
        }
    }

    private var sharpnessColor: Color {
        if photo.sharpnessScore < 100 {
            return .red
        } else if photo.sharpnessScore < 500 {
            return .orange
        } else {
            return .green
        }
    }

    private func loadThumbnail() {
        Task { @MainActor in
            PhotoKitService.shared.loadThumbnail(for: photo.assetIdentifier, size: CGSize(width: 200, height: 200)) { image in
                self.thumbnail = image
            }
        }
    }
}

struct PhotoThumbnailView: View {
    let assetIdentifier: String
    let size: CGSize
    var contentMode: ContentMode = .fill
    /// Optional callback fired exactly once when the thumbnail truly cannot
    /// be loaded — `loadThumbnail` already exhausts `.opportunistic` AND a
    /// `.highQualityFormat` retry before reporting nil, so any nil that
    /// reaches us is genuinely unrenderable. Cells that own the asset's
    /// place in a group should wire this to `store.pruneUnloadableAsset`
    /// so the broken cell vanishes from the UI instead of sitting around
    /// as a gray placeholder.
    var onUnloadable: (() -> Void)? = nil
    @State private var thumbnail: UIImage?
    /// Cancellation handle for the in-flight PHImageManager request.
    /// Held in @State so cell recycle (parent body invalidation) doesn't
    /// drop our reference — when this cell scrolls off-screen we call
    /// `token.cancel()` from `.onDisappear`, freeing the daemon's queue
    /// slot for whatever the user has scrolled INTO view. Without this,
    /// fast-scrolling through the duplicates list piled up hundreds of
    /// stale requests behind the visible cells, which is what produced
    /// the "gray boxes" + "lag after using the section for a while" bug.
    @State private var token: ThumbnailRequestToken?

    /// Synchronous cache hit on the very first body evaluation — eliminates
    /// the harsh grey-placeholder flash when the user has already scrolled
    /// past the cell once. Falls back to async load on miss.
    init(
        assetIdentifier: String,
        size: CGSize,
        contentMode: ContentMode = .fill,
        onUnloadable: (() -> Void)? = nil
    ) {
        self.assetIdentifier = assetIdentifier
        self.size = size
        self.contentMode = contentMode
        self.onUnloadable = onUnloadable
        let cached = AssetThumbnailCache.shared.cached(assetId: assetIdentifier, size: size)
        _thumbnail = State(initialValue: cached)
    }

    var body: some View {
        Group {
            if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .clipped()
            } else {
                // Color.clear — never show a gray skeleton. If the load
                // succeeds, the image replaces this in <50ms for local
                // photos. If the load fails, the cell signals its parent
                // via `onUnloadable` and gets pruned out of the source
                // list entirely, so this Color.clear never lingers on
                // screen as a placeholder.
                Color.clear
            }
        }
        // .id(assetIdentifier) on the *thumbnail* layer so SwiftUI
        // recognizes when a recycled cell has been handed a different
        // asset and rebuilds @State (cancelling the old token + starting
        // a fresh load). Without this, the recycled cell's old @State
        // (with a different asset's image) would persist, leaving the
        // wrong photo painted under the new identifier.
        .id(assetIdentifier)
        .onAppear {
            // Already loaded from synchronous cache hit — skip the async
            // PhotoKit round-trip.
            if thumbnail != nil { return }
            // Don't fire a second request if one is already in flight.
            // SwiftUI can call onAppear twice during a transition and a
            // duplicate request would just queue up another stale daemon
            // call.
            if token != nil && !(token?.isCancelled ?? true) { return }
            let phMode: PHImageContentMode = (contentMode == .fit) ? .aspectFit : .aspectFill
            token = PhotoKitService.shared.loadThumbnailCancellable(
                for: assetIdentifier,
                size: size,
                contentMode: phMode
            ) { image in
                if let image {
                    // Populate the shared cache so the next render
                    // (sibling cells, scroll-back, view rebuild) hits
                    // the synchronous path and never shows a skeleton.
                    AssetThumbnailCache.shared.store(image: image, assetId: assetIdentifier, size: size)
                    self.thumbnail = image
                } else {
                    // Genuine load failure — both opportunistic and the
                    // highQualityFormat retry returned nil. Tell our
                    // owner to prune this cell out of its source list
                    // so the user never sees a gray box claiming
                    // there's something here to clean up.
                    onUnloadable?()
                }
            }
        }
        .onDisappear {
            // Cell scrolled off-screen — cancel the daemon request so a
            // newly-visible cell isn't stuck behind it. The image we
            // already loaded stays in the shared NSCache so scroll-back
            // is instant.
            token?.cancel()
            token = nil
        }
    }
}

#Preview {
    PhotoKitTestView()
}
