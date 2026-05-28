import SwiftUI

struct UnsubscribeListView: View {
    var scope: String = "all"
    @StateObject var emailService = EmailService.shared
    @Environment(\.dismiss) var dismiss
    @State var unsubscribedEmails: Set<String> = []
    @State var keptEmails: Set<String> = []
    @State var isUnsubscribing: String? = nil
    @State var confirmSender: EmailSender? = nil
    // Persist preferences across launches so the filter actually sticks
    @AppStorage("unsubscribe.trashExisting") var confirmTrashExisting: Bool = true
    @AppStorage("unsubscribe.skipConfirmation") var skipConfirmation: Bool = false
    @State var showSettings = false

    // Search + sort
    @State var searchText: String = ""
    @AppStorage("unsubscribe.sortOption") var sortOptionRaw: String = SortOption.mostEmails.rawValue

    var sortOption: SortOption {
        SortOption(rawValue: sortOptionRaw) ?? .mostEmails
    }

    enum SortOption: String, CaseIterable, Identifiable {
        case mostEmails = "Most emails"
        case fewestEmails = "Fewest emails"
        case nameAZ = "Name (A → Z)"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .mostEmails:   return "arrow.down.circle"
            case .fewestEmails: return "arrow.up.circle"
            case .nameAZ:       return "textformat.abc"
            }
        }
    }

    // Scanning state
    @State var displayedEmails: Int = 0
    @State var displayedSenders: Int = 0
    @State var scanTimer: Timer?
    @State var scanPhase: ScanPhase = .waiting

    enum ScanPhase {
        case waiting    // before real data
        case syncing    // real data arrived, animating to final
        case done       // settled
    }

    // Realistic ceiling while waiting — don't let it run away
    let maxFakeEmails = 2500
    let maxFakeSenders = 120

    var filteredSenders: [EmailSender] {
        var result = emailService.senders

        // 1) Hide kept senders (instant client-side hide)
        if !keptEmails.isEmpty {
            result = result.filter { !keptEmails.contains($0.email) }
        }

        // 2) Apply search filter
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.name.lowercased().contains(q) || $0.email.lowercased().contains(q)
            }
        }

        // 3) Apply sort
        switch sortOption {
        case .mostEmails:
            result.sort { $0.count > $1.count }
        case .fewestEmails:
            result.sort { $0.count < $1.count }
        case .nameAZ:
            result.sort { $0.name.lowercased() < $1.name.lowercased() }
        }

        return result
    }

    var body: some View {
        ZStack {
            // Same 3-stop blue-lavender → light-gray gradient as the Email
            // landing page (`EmailCleanerView`) and every other email
            // category detail screen — one canvas across the whole flow.
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

            VStack(spacing: 0) {
                header
                if scanPhase != .done || emailService.isSendersLoading {
                    scanningBanner
                } else {
                    settledBanner
                }
                searchBar
                senderContent
            }
        }
        .blur(radius: (confirmSender != nil || showSettings) ? 18 : 0)
        .animation(.easeOut(duration: 0.22), value: confirmSender != nil)
        .animation(.easeOut(duration: 0.22), value: showSettings)
        .toolbar(.hidden, for: .navigationBar)
        .hidesBottomNavBar()
        .environment(\.colorScheme, .light)
        .task {
            // Sync the kept-sender set from the backend so previously-kept
            // senders are filtered out before we display anything.
            await emailService.loadKeptSenders()
            keptEmails = emailService.keptSenderEmails

            // Always trigger a fresh scan on entry. The 5-minute server-side
            // sender cache was stranding TestFlight users on a stale "53
            // senders" snapshot from their first visit — the prod backend
            // had latched onto a partial scan and the iOS layer never asked
            // it to re-scan because the cache returned data instantly.
            // Passing `refresh: true` bypasses that cache and forces a fresh
            // wave-based scan every time the user opens this screen.
            //
            // We still preserve any senders we already have in memory while
            // the scan runs (the existing fetchSenders polling loop updates
            // `senders` progressively), so the user never sees an empty
            // screen while waiting for the new scan.
            let hasExistingData = !emailService.senders.isEmpty
            if !hasExistingData {
                startScanAnimation()
            } else {
                displayedEmails = emailService.totalSenderEmails
                displayedSenders = emailService.senders.count
                // Scan is still running in the background — keep the live
                // counter on so users see new senders trickling in.
                scanPhase = .syncing
            }
            await emailService.fetchSenders(scope: scope, refresh: true)
            syncToRealNumbers()
        }
        .onChange(of: emailService.senders.count) { _, _ in
            syncToRealNumbers()
        }
        .onChange(of: emailService.isSendersLoading) { _, loading in
            if !loading { syncToRealNumbers() }
        }
        .onDisappear {
            // Nil the reference too so a re-appear doesn't see a stale
            // (already-invalidated) Timer in `scanTimer`. The 0.2s tick
            // body dispatches a Task per fire; bailing the timer
            // promptly + clearing the field is what keeps a backgrounded
            // view from queueing main-queue work after dismiss.
            scanTimer?.invalidate()
            scanTimer = nil
        }
        .sheet(item: $confirmSender) { sender in
            UnsubscribeConfirmSheet(
                sender: sender,
                trashExisting: $confirmTrashExisting,
                skipFuture: $skipConfirmation,
                onCancel: { confirmSender = nil },
                onConfirm: {
                    let s = sender
                    confirmSender = nil
                    Task { await performUnsubscribe(from: s, deleteExisting: confirmTrashExisting) }
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
            .presentationBackground(Color.background)
            .presentationCornerRadius(24)
        }
        .sheet(isPresented: $showSettings) {
            unsubscribeSettingsSheet
                .presentationDetents([.height(580)])
                .presentationDragIndicator(.hidden)
                .presentationCornerRadius(28)
                .presentationBackground(Color.background)
        }
    }

}
