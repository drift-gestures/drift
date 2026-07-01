import Combine
import Foundation

/// Messages that can be delivered to a visible HUD.
enum HUDMessage: Sendable {
    /// Gesture-derived input for the Timer HUD.
    case timerInput(TimerHUDInput)
}

/// A HUD message paired with the destination HUD identifier.
struct TargetedHUDMessage: Sendable {
    /// The HUD that should receive the message.
    let hudID: HUDID
    /// The payload to deliver to the destination HUD.
    let message: HUDMessage
}

/// Publishes targeted HUD messages to SwiftUI views on the main actor.
@MainActor
final class HUDMessageBus: ObservableObject {
    /// Stream of messages emitted by app-level backend event handling.
    let messages = PassthroughSubject<TargetedHUDMessage, Never>()

    /// Sends a message to a specific HUD.
    /// - Parameters:
    ///   - message: The HUD payload to deliver.
    ///   - hudID: The destination HUD identifier.
    func send(_ message: HUDMessage, to hudID: HUDID) {
        messages.send(TargetedHUDMessage(hudID: hudID, message: message))
    }
}

/// Thread-safe mirror of currently visible HUDs for non-main-actor listener code.
final class HUDVisibilityState: @unchecked Sendable {
    /// Protects access to `activeHUDs` across event-tap and main-actor callers.
    private let lock = NSLock()
    /// The HUD identifiers that are currently visible.
    private var activeHUDs: Set<HUDID> = []

    /// Replaces the set of active HUD identifiers.
    /// - Parameter ids: The HUDs that should be treated as visible.
    func setActiveHUDs(_ ids: Set<HUDID>) {
        lock.lock()
        activeHUDs = ids
        lock.unlock()
    }

    /// Checks whether a HUD is currently active.
    /// - Parameter id: The HUD identifier to test.
    /// - Returns: `true` when the HUD is visible.
    func isActive(_ id: HUDID) -> Bool {
        lock.lock()
        let isActive = activeHUDs.contains(id)
        lock.unlock()
        return isActive
    }
}

/// Main-actor source of truth for HUD visibility, custom HUD state, and live trackpad state.
@MainActor
final class HUDStore: ObservableObject {
    /// HUD identifiers currently displayed by `HUDWindowPresenter`.
    @Published private(set) var activeHUDs: Set<HUDID> = []
    /// Custom per-HUD state keyed by HUD raw identifier.
    @Published private(set) var customStates: [String: HUDState] = [:]
    /// Latest trackpad state available to HUD layout and rendering.
    @Published private(set) var trackpadState = TrackpadState.idle

    /// Optional thread-safe mirror used by listener code outside the main actor.
    private let visibilityState: HUDVisibilityState?

    /// Creates a HUD store.
    /// - Parameter visibilityState: Optional cross-thread visibility mirror to keep in sync.
    init(visibilityState: HUDVisibilityState? = nil) {
        self.visibilityState = visibilityState
    }

    /// Marks a HUD as visible.
    /// - Parameter id: The HUD identifier to activate.
    func activate(_ id: HUDID) {
        var nextHUDs = activeHUDs
        nextHUDs.insert(id)
        setActiveHUDs(nextHUDs)
    }

    /// Marks a HUD as hidden.
    /// - Parameter id: The HUD identifier to deactivate.
    func deactivate(_ id: HUDID) {
        var nextHUDs = activeHUDs
        nextHUDs.remove(id)
        setActiveHUDs(nextHUDs)
    }

    /// Toggles a HUD between visible and hidden states.
    /// - Parameter id: The HUD identifier to toggle.
    func toggle(_ id: HUDID) {
        var nextHUDs = activeHUDs
        if activeHUDs.contains(id) {
            nextHUDs.remove(id)
        } else {
            nextHUDs.insert(id)
        }
        setActiveHUDs(nextHUDs)
    }

    /// Stores custom state for a HUD-specific key.
    /// - Parameters:
    ///   - state: The state value to store.
    ///   - key: The custom state key, usually based on a HUD identifier.
    func setCustomState(_ state: HUDState, for key: String) {
        customStates[key] = state
    }

    /// Updates the latest trackpad snapshot exposed to HUD layout and rendering.
    /// - Parameter snapshot: The snapshot most recently received from the input bridge.
    func updateTrackpad(_ snapshot: TrackpadSnapshot) {
        trackpadState.latestSnapshot = snapshot
    }

    /// Replaces active HUDs and synchronizes the optional thread-safe visibility mirror.
    /// - Parameter huds: The next active HUD set.
    private func setActiveHUDs(_ huds: Set<HUDID>) {
        activeHUDs = huds
        visibilityState?.setActiveHUDs(huds)
    }
}
