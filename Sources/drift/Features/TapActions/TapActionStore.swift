import Combine
import Foundation

/// Device-local source of truth for tap/slap action bindings, read synchronously by the runtime
/// coordinator and edited by Settings.
final class TapActionStore: @unchecked Sendable {
    private static let defaultsKey = "drift.tapActionLibrary"
    private let lock = NSLock()
    private let defaults: UserDefaults
    private var library: TapActionLibrary

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode(TapActionLibrary.self, from: data) {
            library = decoded
        } else {
            library = TapActionLibrary()
        }
    }

    /// A snapshot copy of all bindings, safe to read from any thread.
    func snapshot() -> TapActionLibrary {
        lock.withLock { library }
    }

    /// Inserts or replaces a binding by id and persists.
    func upsert(_ binding: TapActionBinding) {
        lock.withLock {
            library.bindings.removeAll { $0.id == binding.id }
            library.bindings.append(binding)
            persistLocked()
        }
    }

    /// Removes a binding by id and persists.
    func remove(id: UUID) {
        lock.withLock {
            library.bindings.removeAll { $0.id == id }
            persistLocked()
        }
    }

    private func persistLocked() {
        guard let data = try? JSONEncoder().encode(library) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

/// Observable Settings adapter over `TapActionStore`.
@MainActor
final class TapActionSettingsModel: ObservableObject {
    /// The current bindings shown and edited by Settings.
    @Published private(set) var bindings: [TapActionBinding]

    private let store: TapActionStore

    init(store: TapActionStore) {
        self.store = store
        bindings = store.snapshot().bindings
    }

    /// Adds a new binding with sensible defaults.
    func addBinding() {
        let binding = TapActionBinding(
            name: "New Tap Action",
            trigger: TapActionTrigger(intensity: .any, side: .any, count: 2),
            action: .keyboardShortcut(keyCode: 49, modifiers: [.command])
        )
        store.upsert(binding)
        bindings = store.snapshot().bindings
    }

    /// Persists an edited binding.
    /// - Parameter binding: The binding to save.
    func save(_ binding: TapActionBinding) {
        store.upsert(binding)
        bindings = store.snapshot().bindings
    }

    /// Deletes a binding.
    /// - Parameter id: The binding identifier to remove.
    func delete(id: UUID) {
        store.remove(id: id)
        bindings = store.snapshot().bindings
    }
}
