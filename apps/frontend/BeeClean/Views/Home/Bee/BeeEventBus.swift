import Foundation
import Combine

struct BeeEvent: Identifiable {
    let id = UUID()
    let kind: Kind
    let timestamp = Date()

    enum Kind {
        case cleanup(count: Int, source: BeeCleanupSource)
        case honeycombFilled(cell: Int)
        case hiveCompleted
        case askBeeStarted
        case askBeeFinished(foundLargeClutter: Bool)
        case inactivity10s
        case inactivity30s
    }
}

final class BeeEventBus: ObservableObject {
    static let shared = BeeEventBus()
    @Published private(set) var lastEvent: BeeEvent?

    private init() {}

    func send(_ kind: BeeEvent.Kind) {
        lastEvent = BeeEvent(kind: kind)
    }
}
