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

/// Thread-safe mirror of the currently visible HUD for non-main-actor listener code.
final class HUDVisibilityState: @unchecked Sendable {
    /// Protects access to `activeHUDID` across event-tap and main-actor callers.
    private let lock = NSLock()
    /// The HUD identifier that is currently visible, if any.
    private var activeHUDID: HUDID?

    /// Replaces the active HUD identifier.
    /// - Parameter id: The HUD that should be treated as visible.
    func setActiveHUDID(_ id: HUDID?) {
        lock.lock()
        activeHUDID = id
        lock.unlock()
    }

    /// The currently active HUD identifier.
    var currentHUDID: HUDID? {
        lock.lock()
        let id = activeHUDID
        lock.unlock()
        return id
    }

    /// Checks whether a HUD is currently active.
    /// - Parameter id: The HUD identifier to test.
    /// - Returns: `true` when the HUD is visible.
    func isActive(_ id: HUDID) -> Bool {
        lock.lock()
        let isActive = activeHUDID == id
        lock.unlock()
        return isActive
    }
}

/// Main-actor source of truth for HUD visibility, custom HUD state, and live trackpad state.
@MainActor
final class HUDStore: ObservableObject {
    /// HUD identifier currently displayed by `HUDWindowPresenter`.
    @Published private(set) var activeHUDID: HUDID?
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

    /// Marks one HUD as visible or clears HUD visibility.
    /// - Parameter id: The HUD identifier to show, or `nil` to hide every HUD.
    func setActiveHUDID(_ id: HUDID?) {
        activeHUDID = id
        visibilityState?.setActiveHUDID(id)
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

    /// Whether a specific HUD is the active HUD.
    /// - Parameter id: The HUD identifier to test.
    /// - Returns: `true` when the HUD is currently active.
    func isActive(_ id: HUDID) -> Bool {
        activeHUDID == id
    }
}
