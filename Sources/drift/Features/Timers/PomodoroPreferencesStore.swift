import Combine
import Foundation

/// Persists editable Pomodoro durations between app launches.
@MainActor
final class PomodoroPreferencesStore: ObservableObject {
    /// Current saved durations.
    @Published private(set) var durations: PomodoroDurations

    /// Backing defaults store.
    private let defaults: UserDefaults
    /// Defaults key for encoded durations.
    private let key: String

    /// Creates a preferences store.
    /// - Parameters:
    ///   - defaults: Defaults domain used for persistence.
    ///   - key: Storage key for the encoded durations.
    init(
        defaults: UserDefaults = .standard,
        key: String = "drift.pomodoro.durations"
    ) {
        self.defaults = defaults
        self.key = key
        durations = Self.loadDurations(from: defaults, key: key)
    }

    /// Saves a complete duration configuration.
    /// - Parameter durations: New duration values.
    func save(_ durations: PomodoroDurations) {
        self.durations = durations
        if let data = try? JSONEncoder().encode(durations) {
            defaults.set(data, forKey: key)
        }
    }

    /// Loads persisted durations, falling back to defaults when data is missing or invalid.
    private static func loadDurations(from defaults: UserDefaults, key: String) -> PomodoroDurations {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(PomodoroDurations.self, from: data)
        else {
            return PomodoroDurations()
        }

        return PomodoroDurations(
            focus: TimerHUDDurationFormatter.clamped(decoded.focus),
            shortBreak: TimerHUDDurationFormatter.clamped(decoded.shortBreak),
            longBreak: TimerHUDDurationFormatter.clamped(decoded.longBreak)
        )
    }
}
