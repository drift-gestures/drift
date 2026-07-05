import AppKit
import Foundation
@preconcurrency import UserNotifications

/// User actions delivered from timer and Pomodoro notifications.
enum TimerAlertAction: Equatable, Sendable {
    /// Dismiss a completed timer alert.
    case dismissTimer(UUID)
    /// Repeat a completed timer.
    case repeatTimer(UUID)
    /// Dismiss the current Pomodoro alert.
    case dismissPomodoro
    /// Toggle Pomodoro pause state.
    case togglePomodoroPause
    /// Skip the current Pomodoro block.
    case skipPomodoro
    /// Reset the current Pomodoro block.
    case resetPomodoro
    /// Stop the active Pomodoro.
    case stopPomodoro
}

/// Owns timer notifications and alert sounds.
@MainActor
final class TimerAlertCenter: NSObject, UNUserNotificationCenterDelegate {
    /// Callback that routes notification actions back to the runtime coordinator.
    var actionHandler: ((TimerAlertAction) -> Void)?

    /// Looping sound used for completed plain timers.
    private var timerSound: NSSound?
    /// Short sound used for Pomodoro transitions.
    private var pomodoroSound: NSSound?

    /// Configures notification categories and permissions.
    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(Self.notificationCategories)
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("drift notification authorization failed: \(error.localizedDescription)")
            } else if !granted {
                print("drift notifications are not authorized.")
            }
        }
    }

    /// Handles a completion event from the runtime coordinator.
    /// - Parameter event: Runtime completion event.
    func handle(_ event: BackgroundTimerRuntimeEvent) {
        switch event {
        case .timerCompleted(let id, let duration):
            playLoopingTimerSound()
            postTimerNotification(id: id, duration: duration)
        case .pomodoroBlockCompleted(_, let block):
            playShortPomodoroSound()
            postPomodoroNotification(block: block)
        }
    }

    /// Stops any currently playing alert sound.
    func stopAlertSound() {
        timerSound?.stop()
        timerSound = nil
        pomodoroSound?.stop()
        pomodoroSound = nil
    }

    /// Receives notification button clicks and notification body clicks.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier
        let notificationIdentifier = response.notification.request.identifier
        Task { @MainActor [weak self] in
            self?.handle(
                actionIdentifier: actionIdentifier,
                notificationIdentifier: notificationIdentifier
            )
        }
    }

    /// Shows notifications even while drift is frontmost.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Routes one notification response.
    @MainActor
    private func handle(actionIdentifier: String, notificationIdentifier: String) {
        stopAlertSound()

        if let timerID = timerID(from: notificationIdentifier) {
            switch actionIdentifier {
            case Self.repeatTimerAction:
                actionHandler?(.repeatTimer(timerID))
            default:
                actionHandler?(.dismissTimer(timerID))
            }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
            return
        }

        switch actionIdentifier {
        case Self.pausePomodoroAction:
            actionHandler?(.togglePomodoroPause)
        case Self.skipPomodoroAction:
            actionHandler?(.skipPomodoro)
        case Self.resetPomodoroAction:
            actionHandler?(.resetPomodoro)
        case Self.stopPomodoroAction:
            actionHandler?(.stopPomodoro)
        default:
            actionHandler?(.dismissPomodoro)
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationIdentifier])
    }

    /// Starts the looping plain-timer sound.
    private func playLoopingTimerSound() {
        stopAlertSound()
        guard let sound = NSSound(named: NSSound.Name("Submarine")) else {
            NSSound.beep()
            return
        }
        sound.loops = true
        sound.play()
        timerSound = sound
    }

    /// Plays a short Pomodoro transition sound.
    private func playShortPomodoroSound() {
        pomodoroSound?.stop()
        guard let sound = NSSound(named: NSSound.Name("Glass")) else {
            NSSound.beep()
            return
        }
        sound.loops = false
        sound.play()
        pomodoroSound = sound
    }

    /// Posts a notification for a completed plain timer.
    private func postTimerNotification(id: UUID, duration: TimeInterval) {
        deliver(
            identifier: Self.timerNotificationPrefix + id.uuidString,
            payload: TimerNotificationPayload(
                title: "Timer",
                body: "\(TimerHUDDurationFormatter.formattedSeconds(duration)) timer finished.",
                categoryIdentifier: Self.timerCategory
            )
        )
    }

    /// Posts a notification for a completed Pomodoro block.
    private func postPomodoroNotification(block: PomodoroBlockKind) {
        deliver(
            identifier: Self.pomodoroNotificationID,
            payload: TimerNotificationPayload(
                title: "Pomodoro",
                body: "\(block.menuTitle) complete.",
                categoryIdentifier: Self.pomodoroCategory
            )
        )
    }

    /// Delivers a notification request after confirming notification authorization.
    private func deliver(identifier: String, payload: TimerNotificationPayload) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Self.addNotification(identifier: identifier, payload: payload)
            case .notDetermined:
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error {
                        print("drift notification authorization failed: \(error.localizedDescription)")
                    }
                    guard granted else {
                        print("drift notifications are not authorized.")
                        return
                    }
                    Self.addNotification(identifier: identifier, payload: payload)
                }
            case .denied:
                print("drift notifications are denied in System Settings.")
            @unknown default:
                print("drift notification authorization status is unknown.")
            }
        }
    }

    /// Adds an already-authorized notification request.
    nonisolated private static func addNotification(identifier: String, payload: TimerNotificationPayload) {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.categoryIdentifier = payload.categoryIdentifier
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("drift notification delivery failed: \(error.localizedDescription)")
            }
        }
    }

    /// Parses a timer UUID from a notification identifier.
    private func timerID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(Self.timerNotificationPrefix) else { return nil }
        return UUID(uuidString: String(identifier.dropFirst(Self.timerNotificationPrefix.count)))
    }

    /// All notification categories used by the app.
    private static var notificationCategories: Set<UNNotificationCategory> {
        [
            UNNotificationCategory(
                identifier: timerCategory,
                actions: [
                    UNNotificationAction(identifier: dismissAction, title: "Dismiss"),
                    UNNotificationAction(identifier: repeatTimerAction, title: "Repeat")
                ],
                intentIdentifiers: []
            ),
            UNNotificationCategory(
                identifier: pomodoroCategory,
                actions: [
                    UNNotificationAction(identifier: dismissAction, title: "Dismiss"),
                    UNNotificationAction(identifier: pausePomodoroAction, title: "Pause/Play"),
                    UNNotificationAction(identifier: skipPomodoroAction, title: "Skip this block"),
                    UNNotificationAction(identifier: resetPomodoroAction, title: "Reset"),
                    UNNotificationAction(identifier: stopPomodoroAction, title: "Stop")
                ],
                intentIdentifiers: []
            )
        ]
    }

    private static let timerNotificationPrefix = "drift.timer."
    private static let pomodoroNotificationID = "drift.pomodoro"
    private static let timerCategory = "DRIFT_TIMER_COMPLETE"
    private static let pomodoroCategory = "DRIFT_POMODORO_COMPLETE"
    private static let dismissAction = "DRIFT_DISMISS"
    private static let repeatTimerAction = "DRIFT_REPEAT_TIMER"
    private static let pausePomodoroAction = "DRIFT_POMODORO_PAUSE"
    private static let skipPomodoroAction = "DRIFT_POMODORO_SKIP"
    private static let resetPomodoroAction = "DRIFT_POMODORO_RESET"
    private static let stopPomodoroAction = "DRIFT_POMODORO_STOP"
}

/// Sendable notification content values built into framework objects at delivery time.
private struct TimerNotificationPayload: Sendable {
    /// Notification title.
    let title: String
    /// Notification body.
    let body: String
    /// Notification category identifier.
    let categoryIdentifier: String
}
