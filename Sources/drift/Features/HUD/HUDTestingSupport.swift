import Foundation

/// Cross-thread state for the HUD opened through temporary testing controls.
final class HUDTestingState: @unchecked Sendable {
    /// Protects testing HUD state across AppKit and listener callback threads.
    private let lock = NSLock()
    /// HUD identifier currently opened by a testing-only control.
    private var activeHUDID: HUDID?

    /// Replaces the testing HUD identifier.
    /// - Parameter id: The testing HUD identifier, or `nil` when testing is inactive.
    func setActiveHUDID(_ id: HUDID?) {
        lock.lock()
        activeHUDID = id
        lock.unlock()
    }

    /// Checks whether a HUD was opened by the testing-only control.
    /// - Parameter id: The HUD identifier to test.
    /// - Returns: `true` when the HUD is currently active for testing.
    func isActive(_ id: HUDID) -> Bool {
        lock.lock()
        let isActive = activeHUDID == id
        lock.unlock()
        return isActive
    }
}

/// Temporary menu-bar testing injection for manually opening HUDs.
@MainActor
final class HUDTestingController {
    /// Runtime HUD handle used instead of direct store mutation.
    private let hudController: HUDController

    /// Creates a testing injector.
    /// - Parameter hudController: HUD lifecycle controller to exercise.
    init(hudController: HUDController) {
        self.hudController = hudController
    }

    /// Toggles a HUD as a testing session.
    /// - Parameter id: The HUD identifier to toggle.
    /// - Returns: `true` when the HUD is active after toggling.
    @discardableResult
    func toggle(_ id: HUDID) -> Bool {
        if hudController.isTesting(id) {
            hudController.close(id)
            return false
        }
        return hudController.open(id, source: .testing)
    }
}
