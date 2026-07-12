import Foundation

/// Device-local source of truth for basic and advanced custom gestures.
final class CustomGestureStore: @unchecked Sendable {
    private static let defaultsKey = "customGestureLibrary"
    private let lock = NSLock()
    private let defaults: UserDefaults
    private var library: CustomGestureLibrary

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(CustomGestureLibrary.self, from: data) {
            library = decoded
        } else {
            library = CustomGestureLibrary()
        }
    }

    func snapshot() -> CustomGestureLibrary {
        lock.withLock { library }
    }

    func replace(with newLibrary: CustomGestureLibrary) {
        lock.withLock {
            library = newLibrary
            persistLocked()
        }
    }

    func upsert(_ gesture: BasicGesture) {
        lock.withLock {
            library.basicGestures.removeAll { $0.id == gesture.id }
            library.basicGestures.append(gesture)
            persistLocked()
        }
    }

    func upsert(_ gesture: AdvancedGesture) {
        lock.withLock {
            var boundedGesture = gesture
            boundedGesture.recordings = Array(gesture.recordings.prefix(5))
            library.advancedGestures.removeAll { $0.id == boundedGesture.id }
            library.advancedGestures.append(boundedGesture)
            persistLocked()
        }
    }

    func removeGesture(id: UUID) {
        lock.withLock {
            library.basicGestures.removeAll { $0.id == id }
            library.advancedGestures.removeAll { $0.id == id }
            persistLocked()
        }
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(library) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// Thread-safe input-mode state shared by the event tap and listener pipeline.
final class CustomGestureModeState: @unchecked Sendable {
    private let lock = NSLock()
    private var activeModifiers: Set<KeyboardModifier> = []
    private var isSuspendedUntilRelease = false
    private let store: CustomGestureStore

    init(store: CustomGestureStore) { self.store = store }

    var isAdvancedModeActive: Bool {
        lock.withLock {
            let required = store.snapshot().advancedActivationModifiers
            return !isSuspendedUntilRelease &&
                !required.isEmpty &&
                activeModifiers.isSuperset(of: required)
        }
    }

    func update(modifiers: Set<KeyboardModifier>) {
        let required = store.snapshot().advancedActivationModifiers
        lock.withLock {
            activeModifiers = modifiers
            if !modifiers.isSuperset(of: required) {
                isSuspendedUntilRelease = false
            }
        }
    }

    /// Disables advanced recognition for the current activation-key hold. Releasing any required
    /// modifier clears the suspension so the next activation behaves normally.
    func suspendUntilModifiersReleased() {
        lock.withLock { isSuspendedUntilRelease = true }
    }
}

/// Thread-safe runtime gate that makes recording and testing exclusive input modes.
final class CustomGestureCaptureState: @unchecked Sendable {
    private let lock = NSLock()
    private var active = false

    var isActive: Bool { lock.withLock { active } }

    func setActive(_ active: Bool) {
        lock.withLock { self.active = active }
    }
}
