import Foundation

/// Synchronous HUD lifecycle handle used by listeners and testing injections.
final class HUDController: @unchecked Sendable {
    /// Main-actor store that renders the current HUD.
    private let hudStore: HUDStore
    /// Message bus used to deliver input to the active HUD view.
    private let hudMessages: HUDMessageBus
    /// Thread-safe visibility mirror checked from listener callback threads.
    private let visibilityState: HUDVisibilityState
    /// Optional testing session state.
    private let testingState: HUDTestingState
    /// Protects active session state across listener, menu, and event-tap callbacks.
    private let lock = NSLock()
    /// Current HUD session, if any.
    private var activeSession: HUDSession?

    /// Creates a controller for one global HUD session.
    /// - Parameters:
    ///   - hudStore: Store that drives AppKit/SwiftUI presentation.
    ///   - hudMessages: Message bus injected into HUD views.
    ///   - visibilityState: Thread-safe mirror used by non-main-actor listeners.
    ///   - testingState: Thread-safe testing-only state.
    init(
        hudStore: HUDStore,
        hudMessages: HUDMessageBus,
        visibilityState: HUDVisibilityState,
        testingState: HUDTestingState
    ) {
        self.hudStore = hudStore
        self.hudMessages = hudMessages
        self.visibilityState = visibilityState
        self.testingState = testingState
    }

    /// The active HUD identifier, if one is open.
    var activeHUDID: HUDID? {
        lock.lock()
        let id = activeSession?.id
        lock.unlock()
        return id
    }

    /// The active HUD session, if one is open.
    private var currentSession: HUDSession? {
        lock.lock()
        let session = activeSession
        lock.unlock()
        return session
    }

    /// Opens a HUD when no different HUD is already active.
    /// - Parameters:
    ///   - id: The HUD identifier to open.
    ///   - source: The source responsible for the session.
    ///   - state: Initial state to provide to the HUD content.
    /// - Returns: `true` when the requested HUD is now the active HUD.
    @discardableResult
    func open(_ id: HUDID, source: HUDSessionSource, state: HUDState = HUDState()) -> Bool {
        lock.lock()
        if let activeSession, activeSession.id != id {
            lock.unlock()
            return false
        }
        activeSession = HUDSession(id: id, source: source, state: state)
        visibilityState.setActiveHUDID(id)
        if source == .testing {
            testingState.setActiveHUDID(id)
        } else if testingState.isActive(id) {
            testingState.setActiveHUDID(nil)
        }
        lock.unlock()

        syncStoreToCurrentSession()
        return true
    }

    /// Closes a HUD when it is the active session.
    /// - Parameter id: The HUD identifier to close.
    /// - Returns: `true` when the HUD was active and is now closed.
    @discardableResult
    func close(_ id: HUDID) -> Bool {
        lock.lock()
        guard activeSession?.id == id else {
            lock.unlock()
            return false
        }
        activeSession = nil
        visibilityState.setActiveHUDID(nil)
        testingState.setActiveHUDID(nil)
        lock.unlock()

        syncStoreToCurrentSession()
        return true
    }

    /// Sends a message to a HUD only if it is still the active HUD.
    /// - Parameters:
    ///   - message: The message payload.
    ///   - id: The destination HUD identifier.
    /// - Returns: `true` if the message was accepted for delivery.
    @discardableResult
    func send(_ message: HUDMessage, to id: HUDID) -> Bool {
        guard isActive(id) else { return false }
        Task { @MainActor [weak self] in
            guard let self, self.isActive(id) else { return }
            self.hudMessages.send(message, to: id)
        }
        return true
    }

    /// Checks whether a HUD is currently active.
    /// - Parameter id: The HUD identifier to test.
    /// - Returns: `true` when the HUD is active.
    func isActive(_ id: HUDID) -> Bool {
        visibilityState.isActive(id)
    }

    /// Checks whether a HUD was opened through a testing injection.
    /// - Parameter id: The HUD identifier to test.
    /// - Returns: `true` when the HUD session came from testing.
    func isTesting(_ id: HUDID) -> Bool {
        testingState.isActive(id)
    }

    /// Schedules main-actor rendering state to converge to the current synchronous state.
    private func syncStoreToCurrentSession() {
        let session = currentSession
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let session {
                self.hudStore.setCustomState(session.state, for: session.id.rawValue)
            }
            self.hudStore.setActiveHUDID(session?.id)
        }
    }
}

/// One active HUD session.
private struct HUDSession: Sendable {
    /// Active HUD identifier.
    let id: HUDID
    /// Source that opened the session.
    let source: HUDSessionSource
    /// Initial state to provide to the HUD content.
    let state: HUDState
}
