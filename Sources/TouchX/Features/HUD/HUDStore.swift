import Combine
import Foundation

final class HUDVisibilityState: @unchecked Sendable {
    private let lock = NSLock()
    private var activeHUDs: Set<HUDID> = []

    func setActiveHUDs(_ ids: Set<HUDID>) {
        lock.lock()
        activeHUDs = ids
        lock.unlock()
    }

    func isActive(_ id: HUDID) -> Bool {
        lock.lock()
        let isActive = activeHUDs.contains(id)
        lock.unlock()
        return isActive
    }
}

@MainActor
final class HUDStore: ObservableObject {
    @Published private(set) var activeHUDs: Set<HUDID> = []
    @Published private(set) var customStates: [String: HUDState] = [:]
    @Published private(set) var trackpadState = TrackpadState.idle
    @Published private(set) var latestTimerHUDInput: TimerHUDInput?

    private let visibilityState: HUDVisibilityState?

    init(visibilityState: HUDVisibilityState? = nil) {
        self.visibilityState = visibilityState
    }

    func activate(_ id: HUDID) {
        var nextHUDs = activeHUDs
        nextHUDs.insert(id)
        setActiveHUDs(nextHUDs)
    }

    func deactivate(_ id: HUDID) {
        var nextHUDs = activeHUDs
        nextHUDs.remove(id)
        setActiveHUDs(nextHUDs)
    }

    func toggle(_ id: HUDID) {
        var nextHUDs = activeHUDs
        if activeHUDs.contains(id) {
            nextHUDs.remove(id)
        } else {
            nextHUDs.insert(id)
        }
        setActiveHUDs(nextHUDs)
    }

    func setCustomState(_ state: HUDState, for key: String) {
        customStates[key] = state
    }

    func updateTrackpad(_ snapshot: TrackpadSnapshot) {
        trackpadState.latestSnapshot = snapshot
    }

    func handle(_ event: BackendEvent) {
        switch event {
        case .timerHUDActivationRequested:
            activate(TimerHUDDefinition.hudID)
        case .timerHUDInput(let input):
            latestTimerHUDInput = input
        }
    }

    private func setActiveHUDs(_ huds: Set<HUDID>) {
        activeHUDs = huds
        visibilityState?.setActiveHUDs(huds)
    }
}
