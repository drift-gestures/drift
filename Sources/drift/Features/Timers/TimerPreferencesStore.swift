import Combine
import Foundation

/// Persists Timer defaults independently from active timer sessions.
@MainActor
final class TimerPreferencesStore: ObservableObject {
    /// Duration selected when the Timer HUD first opens.
    @Published private(set) var defaultDuration: Int

    private let defaults: UserDefaults
    private let defaultDurationKey: String

    init(
        defaults: UserDefaults = .standard,
        defaultDurationKey: String = "drift.timer.defaultDuration"
    ) {
        self.defaults = defaults
        self.defaultDurationKey = defaultDurationKey
        defaultDuration = TimerHUDDurationFormatter.clamped(
            defaults.integer(forKey: defaultDurationKey)
        )
    }

    /// Saves the duration selected for newly opened Timer HUDs.
    func saveDefaultDuration(_ duration: Int) {
        let duration = TimerHUDDurationFormatter.clamped(duration)
        defaultDuration = duration
        defaults.set(duration, forKey: defaultDurationKey)
    }
}
