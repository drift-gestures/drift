import CoreGraphics
import SwiftUI

/// Timer-specific state carried when opening the Timer HUD.
struct TimerHUDState: Equatable, Sendable {
    /// Initial mounted mode for this HUD presentation.
    let initialMode: TimerHUDMode

    /// Creates Timer HUD state.
    /// - Parameter initialMode: Initial mounted mode for the HUD.
    init(initialMode: TimerHUDMode = .timer) {
        self.initialMode = initialMode
    }
}

/// Timer-specific HUD messages.
enum TimerHUDMessage: Sendable {
    /// Gesture-derived input for the Timer HUD.
    case input(TimerHUDInput)
    /// Keyboard request to run the visible Return-style default action.
    case defaultAction
}

extension HUDMessage {
    /// Creates a Timer HUD message.
    /// - Parameter message: Timer-specific message payload.
    /// - Returns: Type-erased HUD message.
    static func timer(_ message: TimerHUDMessage) -> HUDMessage {
        HUDMessage(message)
    }

    /// Timer HUD message payload, when this message belongs to the Timer HUD.
    var timerHUDMessage: TimerHUDMessage? {
        payload(as: TimerHUDMessage.self)
    }
}

/// HUD definition for the Timer HUD surface.
struct TimerHUDDefinition: HudDefinition {
    /// Stable identifier used to register, show, hide, and message the Timer HUD.
    static let hudID = HUDID(rawValue: "timer")

    /// The Timer HUD identifier required by `HudDefinition`.
    let id = hudID
    /// HUD controller used to close the setup surface after Start.
    private let hudController: HUDController
    /// App-wide background workers available to this HUD.
    private let workers: AppBackgroundWorkers
    /// Fixed Timer HUD window size, including the tick rail, gap, and controls.
    let size = CGSize(width: TimerHUDStyle.timerRailWidth + TimerHUDStyle.timerGridGap + TimerHUDStyle.timerButtonWidth, height: TimerHUDStyle.windowHeight)

    /// Creates the Timer HUD definition.
    /// - Parameters:
    ///   - hudController: HUD lifecycle handle.
    ///   - workers: App-wide background worker container.
    init(
        hudController: HUDController,
        workers: AppBackgroundWorkers
    ) {
        self.hudController = hudController
        self.workers = workers
    }

    /// Positions the Timer HUD near the left side of the visible screen.
    /// - Parameter context: Layout inputs for the current screen.
    /// - Returns: The Timer HUD window origin.
    func position(in context: HUDLayoutContext) -> CGPoint {
        CGPoint(
            x: 20,
            y: context.screenFrame.maxY/2 - size.height/2
        )
    }

    /// Builds the Timer HUD SwiftUI content.
    /// - Parameter context: Render context supplied by the presenter.
    /// - Returns: The Timer HUD view.
    func content(context: HUDContext) -> some View {
        let timerState = context.state.payload(as: TimerHUDState.self) ?? TimerHUDState()
        let timerWorker = workers.timer
        TimerHUDRuntimeView(
            screenSize: size,
            timerWorker: timerWorker,
            backgroundTimers: timerWorker.backgroundTimers,
            pomodoroPreferences: timerWorker.pomodoroPreferences,
            hudController: hudController,
            initialMode: timerState.initialMode
        )
    }
}

/// Runtime adapter owned by `TimerHUDDefinition` that keeps object ownership out of Timer HUD components.
private struct TimerHUDRuntimeView: View {
    /// Size used by the fade overlay to cover the visible Timer HUD area.
    let screenSize: CGSize
    /// App-owned Timer runtime worker.
    let timerWorker: TimerBackgroundWorker
    /// Runtime timer coordinator.
    @ObservedObject var backgroundTimers: BackgroundTimerCoordinator
    /// Persisted Pomodoro duration preferences.
    @ObservedObject var pomodoroPreferences: PomodoroPreferencesStore
    /// HUD lifecycle controller.
    let hudController: HUDController
    /// Initial mounted mode for this HUD presentation.
    let initialMode: TimerHUDMode

    var body: some View {
        TimerHUDView(
            screenSize: screenSize,
            initialMode: initialMode,
            initialPomodoroDurations: pomodoroPreferences.durations,
            pomodoroSession: backgroundTimers.pomodoroSession,
            pomodoroRemainingSeconds: backgroundTimers.pomodoroRemainingSeconds(),
            savePomodoroDurations: savePomodoroDurations,
            startTimer: startTimer,
            startPomodoro: startPomodoro,
            togglePomodoroPause: backgroundTimers.togglePomodoroPause,
            skipPomodoroBlock: backgroundTimers.skipPomodoroBlock,
            stopPomodoro: backgroundTimers.stopPomodoro
        )
    }

    /// Saves duration edits and applies them to future active Pomodoro blocks.
    /// - Parameter durations: Updated Pomodoro durations.
    private func savePomodoroDurations(_ durations: PomodoroDurations) {
        timerWorker.savePomodoroDurations(durations)
    }

    /// Starts a background timer and closes the HUD on success.
    /// - Parameter minutes: Timer duration in minutes.
    /// - Returns: `true` when the timer started.
    private func startTimer(minutes: Int) -> Bool {
        guard backgroundTimers.startTimer(minutes: minutes) != nil else { return false }
        _ = hudController.close(TimerHUDDefinition.hudID)
        return true
    }

    /// Starts a Pomodoro session and closes the HUD on success.
    /// - Parameter durations: Configured Pomodoro durations.
    /// - Returns: `true` when the Pomodoro session started.
    private func startPomodoro(durations: PomodoroDurations) -> Bool {
        guard timerWorker.startPomodoro(durations: durations) else { return false }
        _ = hudController.close(TimerHUDDefinition.hudID)
        return true
    }
}
