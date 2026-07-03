import AppKit
import CoreGraphics
import SwiftUI

/// HUD definition and runtime owner for the Timer HUD surface.
@MainActor
final class TimerHUDDefinition: HudDefinition {
    /// Stable identifier used to register, show, hide, and message the Timer HUD.
    nonisolated static let hudID = HUDID(rawValue: "timer")

    /// The Timer HUD identifier required by `HudDefinition`.
    nonisolated let id = hudID
    /// Runtime coordinator that starts background timers after setup.
    private let backgroundTimers = BackgroundTimerCoordinator()
    /// Store for persisted Pomodoro duration preferences.
    private let pomodoroPreferences = PomodoroPreferencesStore()
    /// Notification and sound handler for completed timers.
    private let timerAlertCenter = TimerAlertCenter()
    /// HUD controller used to close the setup surface after Start.
    private let hudController: HUDController
    /// Dedicated runtime menu-bar items for Timer and Pomodoro.
    private lazy var timerMenuBarController = TimerMenuBarController(
        coordinator: backgroundTimers,
        alertCenter: timerAlertCenter
    )
    /// Fixed Timer HUD window size, including the tick rail, gap, and controls.
    nonisolated let size = CGSize(width: TimerHUDStyle.timerTickWidth + TimerHUDStyle.timerGridGap + TimerHUDStyle.timerButtonWidth, height: TimerHUDStyle.windowHeight)

    /// Creates the Timer HUD definition.
    /// - Parameter hudController: HUD lifecycle handle.
    init(hudController: HUDController) {
        self.hudController = hudController
    }

    /// Starts Timer/Pomodoro runtime services after the app launches.
    func applicationDidFinishLaunching() {
        configureBackgroundTimerRuntime()
        timerMenuBarController.start()
        timerAlertCenter.start()
    }

    /// Positions the Timer HUD near the left side of the visible screen.
    /// - Parameter context: Layout inputs for the current screen.
    /// - Returns: The Timer HUD window origin.
    nonisolated func position(in context: HUDLayoutContext) -> CGPoint {
        CGPoint(
            x: 20,
            y: context.screenFrame.maxY/2 - size.height/2
        )
    }

    /// Builds the Timer HUD SwiftUI content.
    /// - Parameter context: Render context supplied by the presenter.
    /// - Returns: The Timer HUD view.
    func content(context: HUDContext) -> some View {
        TimerHUDView(
            screenSize: size,
            backgroundTimers: backgroundTimers,
            pomodoroPreferences: pomodoroPreferences,
            hudController: hudController,
            initialMode: TimerHUDMode(rawValue: context.state.initialMode ?? "") ?? .timer
        )
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
