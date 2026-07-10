import Combine
import CoreGraphics
import Foundation

/// Message payload that can be delivered to a visible HUD.
struct HUDMessage: Sendable {
    /// HUD-specific message payload.
    private let payload: any Sendable

    /// Creates a HUD message from a HUD-specific payload.
    /// - Parameter payload: Message payload interpreted by the destination HUD.
    init<Payload: Sendable>(_ payload: Payload) {
        self.payload = payload
    }

    /// Reads a HUD-specific payload if it matches the requested type.
    /// - Parameter type: Payload type to read.
    /// - Returns: The typed payload, or `nil` when this message carries another payload.
    func payload<Payload: Sendable>(as type: Payload.Type = Payload.self) -> Payload? {
        payload as? Payload
    }
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
    /// Optional rendered size override keyed by HUD identifier.
    @Published private(set) var sizeOverrides: [HUDID: CGSize] = [:]
    /// Optional AppKit behavior override keyed by HUD identifier.
    @Published private(set) var windowBehaviorOverrides: [HUDID: HUDWindowBehavior] = [:]
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

    /// Overrides the rendered size for a HUD, or clears the override.
    /// - Parameters:
    ///   - size: The size to render, or `nil` to use the HUD definition default.
    ///   - id: The HUD whose size should be overridden.
    func setSizeOverride(_ size: CGSize?, for id: HUDID) {
        if let size {
            sizeOverrides[id] = size
        } else {
            sizeOverrides.removeValue(forKey: id)
        }
    }

    /// Returns a size override for a HUD if one is active.
    /// - Parameter id: The HUD identifier to inspect.
    /// - Returns: The overridden size, or `nil` when the HUD should use its default.
    func sizeOverride(for id: HUDID) -> CGSize? {
        sizeOverrides[id]
    }

    /// Overrides the AppKit behavior for a HUD, or clears the override.
    /// - Parameters:
    ///   - behavior: Window behavior to apply, or `nil` to use the default passive behavior.
    ///   - id: The HUD whose window behavior should be overridden.
    func setWindowBehaviorOverride(_ behavior: HUDWindowBehavior?, for id: HUDID) {
        if let behavior {
            windowBehaviorOverrides[id] = behavior
        } else {
            windowBehaviorOverrides.removeValue(forKey: id)
        }
    }

    /// Returns a window behavior override for a HUD if one is active.
    /// - Parameter id: The HUD identifier to inspect.
    /// - Returns: The overridden behavior, or `.passive` by default.
    func windowBehavior(for id: HUDID) -> HUDWindowBehavior {
        windowBehaviorOverrides[id] ?? .passive
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
