import Foundation

/// App-owned background worker for Timer and Pomodoro runtime services.
@MainActor
final class TimerBackgroundWorker: HUDBackgroundWorker {
    /// Store for persisted Timer defaults.
    let timerPreferences = TimerPreferencesStore()
    /// Runtime coordinator for active background timers.
    let backgroundTimers = BackgroundTimerCoordinator()
    /// Store for persisted Pomodoro duration preferences.
    let pomodoroPreferences = PomodoroPreferencesStore()

    /// Notification and sound handler for completed timers.
    private let timerAlertCenter = TimerAlertCenter()
    /// Dedicated runtime menu-bar items for Timer and Pomodoro.
    private lazy var timerMenuBarController = TimerMenuBarController(
        coordinator: backgroundTimers,
        alertCenter: timerAlertCenter
    )

    /// Starts Timer/Pomodoro runtime services after the app launches.
    func applicationDidFinishLaunching() {
        configureBackgroundTimerRuntime()
        timerMenuBarController.start()
        timerAlertCenter.start()
    }

    /// Saves duration edits and applies them to future active Pomodoro blocks.
    /// - Parameter durations: Updated Pomodoro durations.
    func savePomodoroDurations(_ durations: PomodoroDurations) {
        pomodoroPreferences.save(durations)
        backgroundTimers.updatePomodoroDurations(durations)
    }

    /// Starts a Pomodoro session.
    /// - Parameter durations: Configured Pomodoro durations.
    /// - Returns: `true` when a session was started.
    @discardableResult
    func startPomodoro(durations: PomodoroDurations) -> Bool {
        guard backgroundTimers.startPomodoro(durations: durations) else { return false }
        pomodoroPreferences.save(durations)
        return true
    }

    /// Connects runtime completion events and notification actions.
    private func configureBackgroundTimerRuntime() {
        backgroundTimers.eventHandler = { [weak self] event in
            self?.timerAlertCenter.handle(event)
            self?.timerMenuBarController.syncStatusItems()
        }
        timerAlertCenter.actionHandler = { [weak self] action in
            self?.handleTimerAlertAction(action)
        }
    }

    /// Applies an action selected from a timer notification.
    /// - Parameter action: Notification action to apply.
    private func handleTimerAlertAction(_ action: TimerAlertAction) {
        timerAlertCenter.stopAlertSound()
        switch action {
        case .dismissTimer(let id):
            backgroundTimers.dismissTimer(id: id)
        case .repeatTimer(let id):
            backgroundTimers.repeatTimer(id: id)
        case .dismissPomodoro:
            break
        case .togglePomodoroPause:
            backgroundTimers.togglePomodoroPause()
        case .skipPomodoro:
            backgroundTimers.skipPomodoroBlock()
        case .resetPomodoro:
            backgroundTimers.resetPomodoroBlock()
        case .stopPomodoro:
            backgroundTimers.stopPomodoro()
        }
        timerMenuBarController.syncStatusItems()
    }
}
