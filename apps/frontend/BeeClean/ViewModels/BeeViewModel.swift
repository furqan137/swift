import SwiftUI
import Combine

final class BeeViewModel: ObservableObject {
    static let shared = BeeViewModel()

    @AppStorage("bee_totalCleanupProgress") private var totalProgressStored = 0
    @AppStorage("bee_lastDateKey") private var lastDateKeyStored = ""
    @AppStorage("bee_persistedStageRaw") private var persistedStageRaw: Int = 0

    // MARK: - Honeycomb (daily action counter — gamification only)
    @Published var totalProgress = 0
    @Published var filledCells = 0
    @Published var dripActive = false
    @Published var currentCellProgress: Double = 0

    // MARK: - Stage (driven by coin progress — see ProgressManager / applyBeeStage)
    @Published var stage: BeeStage = .stage1

    // MARK: - Animation state
    @Published var state: BeeMascotState = .idle
    @Published var activeBehavior: BeeIdleBehavior = .hoverSway

    @Published var rewardPulse: RewardPulseType = .none
    @Published var rewardToken = 0
    @Published var deleteReactionToken = 0
    @Published var stateToken = 0
    @Published var behaviorToken = 0
    @Published var evolutionToken = 0
    /// Incremented whenever the bee regresses a stage — drives the devolve
    /// motion in `BeeMascotView` (droop + dim glow, no sparkle).
    @Published var devolutionToken = 0
    /// Incremented on a level-up — drives the dedicated rebirth/recycle
    /// celebration (NOT a devolve) when the bee resets to stage1 for the
    /// next level loop.
    @Published var levelUpToken = 0
    @Published var orbitToken = 0
    @Published var sparkleToken = 0

    @Published var encourageToken = 0
    @Published var glowIntensity: Double = 0

    private var cancellables = Set<AnyCancellable>()
    private var idleTimer: Timer?
    private var inactivity10Timer: Timer?
    private var inactivity30Timer: Timer?

    private init() {
        checkDayReset()
        hydrateHoneycomb()
        restorePersistedStage()
        bindEvents()
        resetInactivityTimers()
    }

    /// Drive the bee's stage from the live Clean Bar percent (via
    /// `ProgressManager`). Plays the evolve choreography as the bar fills
    /// within a level. (A level-up reset is handled by `playLevelUp`, never
    /// here, so it never reads as a downgrade.)
    @MainActor
    func applyBeeStage(_ newStage: BeeStage) {
        guard newStage != stage else { return }

        let isUpgrade = newStage.rawValue > stage.rawValue
        stage = newStage
        persistedStageRaw = newStage.rawValue

        if isUpgrade {
            transition(to: .evolving, autoReturnAfter: 1.1)
            evolutionToken += 1
            sparkleToken += 1
            glowIntensity = max(glowIntensity, 0.4)
        } else {
            transition(to: .devolving, autoReturnAfter: 1.2)
            devolutionToken += 1
            BeeHaptics.lightTap()
            glowIntensity = max(0.02, glowIntensity * 0.5)
        }
    }

    /// Set the stage to match the Clean Bar with no transition choreography —
    /// used on launch/restore so the bee never shows a stale persisted stage.
    /// Animated changes (coin awards / level-ups) still go through
    /// `applyBeeStage` / `playLevelUp`.
    @MainActor
    func syncStage(_ newStage: BeeStage) {
        guard newStage != stage else { return }
        stage = newStage
        persistedStageRaw = newStage.rawValue
    }

    /// Celebratory level-up: the bee is reborn into the next level loop and
    /// resets to stage1. This is deliberately NOT the devolve choreography —
    /// it's a sparkle/glow burst + celebrate so the moment feels like
    /// "transform → fresh start", never "bee got weaker".
    @MainActor
    func playLevelUp(resettingTo newStage: BeeStage) {
        stage = newStage
        persistedStageRaw = newStage.rawValue
        levelUpToken += 1
        evolutionToken += 1
        sparkleToken += 1
        rewardPulse = .hiveComplete
        rewardToken += 1
        glowIntensity = 1.0
        BeeHaptics.lightTap()
        transition(to: .celebrating, autoReturnAfter: 1.4)
    }

    func checkDayReset() {
        let today = DateKeys.todayKey
        if lastDateKeyStored != today {
            totalProgressStored = 0
            lastDateKeyStored = today
        }
    }

    private func hydrateHoneycomb() {
        totalProgress = BeeEngine.clamp(totalProgressStored)
        filledCells = BeeEngine.filledCells(for: totalProgress)
        dripActive = totalProgress >= BeeEngine.dripThreshold
        currentCellProgress = BeeEngine.progressWithinCurrentCell(total: totalProgress)
    }

    private func restorePersistedStage() {
        stage = BeeStage(rawValue: persistedStageRaw) ?? .stage1
    }

    private func bindEvents() {
        BeeEventBus.shared.$lastEvent
            .compactMap { $0 }
            // Combine delivers on the upstream's queue; hop to main so
            // `handle` (which drives @Published state + main-only
            // haptics) is always called on the right actor under
            // strict concurrency.
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    self?.handle(event)
                }
            }
            .store(in: &cancellables)
    }

    func registerDeletion(count: Int = 1) {
        registerCleanup(count: count, source: .photoDelete)
    }

    func registerCleanup(count: Int = 1, source: BeeCleanupSource) {
        BeeEventBus.shared.send(.cleanup(count: count, source: source))
    }

    func startThinking() {
        transition(to: .thinking)
        orbitToken += 1
    }

    func finishThinking(foundLargeClutter: Bool) {
        BeeEventBus.shared.send(.askBeeFinished(foundLargeClutter: foundLargeClutter))
    }

    func triggerRandomBehavior() {
        guard state == .idle else { return }
        activeBehavior = .randomWeighted()
        behaviorToken += 1
    }

    func resetProgress() {
        totalProgressStored = 0
        hydrateHoneycomb()
        state = .idle
        rewardPulse = .none
        glowIntensity = 0
        stateToken += 1
    }

    @MainActor
    private func handle(_ event: BeeEvent) {
        resetInactivityTimers()

        switch event.kind {
        case let .cleanup(count, source):
            applyCleanup(count: count, source: source)

        case .askBeeStarted:
            startThinking()

        case let .askBeeFinished(foundLargeClutter):
            transition(to: foundLargeClutter ? .celebrating : .reacting, autoReturnAfter: foundLargeClutter ? 1.2 : 0.8)
            sparkleToken += 1
            if foundLargeClutter {
                glowIntensity = 0.65
                rewardPulse = .cellFilled(max(filledCells, 1))
                rewardToken += 1
            }

        case .inactivity10s:
            transition(to: .reacting, autoReturnAfter: 1.0)
            activeBehavior = .curiousTilt
            behaviorToken += 1

        case .inactivity30s:
            transition(to: .encouraging, autoReturnAfter: 1.3)
            activeBehavior = .hoverLoop
            behaviorToken += 1
            encourageToken += 1

        case let .honeycombFilled(cell):
            rewardPulse = .cellFilled(cell)
            rewardToken += 1
            sparkleToken += 1
            transition(to: .celebrating, autoReturnAfter: 1.0)

        case .hiveCompleted:
            rewardPulse = .hiveComplete
            rewardToken += 1
            glowIntensity = 0.95
            transition(to: .evolving, autoReturnAfter: 1.4)
            evolutionToken += 1
        }
    }

    // @MainActor for the same reason as applyStageRecalc — drives
    // @Published state + BeeHaptics, both main-only.
    @MainActor
    private func applyCleanup(count: Int, source: BeeCleanupSource) {
        let old = totalProgress
        let new = BeeEngine.clamp(old + count)
        guard new != old else { return }

        totalProgress = new
        totalProgressStored = new
        dripActive = new >= BeeEngine.dripThreshold
        currentCellProgress = BeeEngine.progressWithinCurrentCell(total: new)
        deleteReactionToken += 1
        sparkleToken += 1
        BeeHaptics.lightTap()

        transition(to: .reacting, autoReturnAfter: 0.55)

        let newFilledCells = BeeEngine.filledCells(for: new)
        filledCells = newFilledCells

        if BeeEngine.didActivateDrip(old: old, new: new) {
            glowIntensity = max(glowIntensity, 0.25)
        }

        BeeEngine.crossedThresholds(old: old, new: new).forEach { threshold in
            if threshold >= BeeEngine.maxProgress {
                BeeEventBus.shared.send(.hiveCompleted)
            } else if let cell = BeeEngine.cellIndexFilled(onCrossing: threshold) {
                BeeEventBus.shared.send(.honeycombFilled(cell: cell))
            }
        }

        if source == .compression || source == .emailCleanup {
            activeBehavior = .glanceToMeter
            behaviorToken += 1
        }
    }

    private func transition(to newState: BeeMascotState, autoReturnAfter delay: TimeInterval? = nil) {
        state = newState
        stateToken += 1

        if let delay {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                self.state = .idle
                self.stateToken += 1
            }
        }
    }

    private func resetInactivityTimers() {
        inactivity10Timer?.invalidate()
        inactivity30Timer?.invalidate()

        inactivity10Timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { _ in
            BeeEventBus.shared.send(.inactivity10s)
        }

        inactivity30Timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { _ in
            BeeEventBus.shared.send(.inactivity30s)
        }
    }
}
