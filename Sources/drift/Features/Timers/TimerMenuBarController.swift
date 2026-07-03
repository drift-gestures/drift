import AppKit
import Combine
import Foundation

/// Presents background timers and Pomodoro sessions in dedicated menu-bar items.
@MainActor
final class TimerMenuBarController: NSObject, NSMenuDelegate {
    /// Runtime source of truth.
    private let coordinator: BackgroundTimerCoordinator
    /// Alert center used to stop sounds when menu actions handle completed work.
    private let alertCenter: TimerAlertCenter
    /// Timer status item.
    private var timerStatusItem: NSStatusItem?
    /// Pomodoro status item.
    private var pomodoroStatusItem: NSStatusItem?
    /// Runtime update subscription.
    private var cancellable: AnyCancellable?

    /// Creates a menu-bar controller.
    /// - Parameters:
    ///   - coordinator: Background timer coordinator.
    ///   - alertCenter: Alert center for notification/sound side effects.
    init(coordinator: BackgroundTimerCoordinator, alertCenter: TimerAlertCenter) {
        self.coordinator = coordinator
        self.alertCenter = alertCenter
    }

    /// Starts observing runtime state.
    func start() {
        guard cancellable == nil else { return }
        cancellable = coordinator.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.syncStatusItems()
            }
        }
        syncStatusItems()
    }

    /// Synchronizes both runtime status items.
    func syncStatusItems() {
        syncTimerStatusItem()
        syncPomodoroStatusItem()
    }

    /// Creates, updates, or removes the plain timer status item.
    private func syncTimerStatusItem() {
        if coordinator.timers.isEmpty {
            if let timerStatusItem {
                NSStatusBar.system.removeStatusItem(timerStatusItem)
                self.timerStatusItem = nil
            }
            return
        }

        let item = timerStatusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        timerStatusItem = item
        item.button?.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Timers")
        item.button?.image?.isTemplate = true
        item.button?.title = " " + timerStatusTitle
        item.menu = makeTimerMenu()
    }

    /// Creates, updates, or removes the Pomodoro status item.
    private func syncPomodoroStatusItem() {
        guard let session = coordinator.pomodoroSession else {
            if let pomodoroStatusItem {
                NSStatusBar.system.removeStatusItem(pomodoroStatusItem)
                self.pomodoroStatusItem = nil
            }
            return
        }

        let item = pomodoroStatusItem ?? NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        pomodoroStatusItem = item
        item.button?.image = NSImage(
            systemSymbolName: session.currentBlock.symbolName,
            accessibilityDescription: session.currentBlock.menuTitle
        )
        item.button?.image?.isTemplate = true
        item.button?.title = " " + formatSeconds(coordinator.pomodoroRemainingSeconds())
        item.menu = makePomodoroMenu(session: session)
    }

    /// Title shown in the plain timer status item.
    private var timerStatusTitle: String {
        let activeTimers = coordinator.timers.filter { !$0.isCompleted }
        if activeTimers.count > 1 {
            return "(\(activeTimers.count))"
        }
        guard let timer = activeTimers.first ?? coordinator.timers.first else {
            return ""
        }
        return timer.isCompleted ? "Done" : formatSeconds(coordinator.remainingSeconds(for: timer))
    }

    /// Builds the timer dropdown menu.
    private func makeTimerMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        for timer in coordinator.timers {
            let remaining = coordinator.remainingSeconds(for: timer)
            let title = timer.isCompleted ? "Timer finished" : "Timer \(formatSeconds(remaining))"
            let titleItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)

            if !timer.isCompleted {
                let pauseItem = NSMenuItem(
                    title: timer.isPaused ? "Play" : "Pause",
                    action: #selector(toggleTimerPause(_:)),
                    keyEquivalent: ""
                )
                pauseItem.target = self
                pauseItem.representedObject = timer.id.uuidString
                menu.addItem(pauseItem)
            } else {
                let repeatItem = NSMenuItem(
                    title: "Repeat",
                    action: #selector(repeatTimer(_:)),
                    keyEquivalent: ""
                )
                repeatItem.target = self
                repeatItem.representedObject = timer.id.uuidString
                menu.addItem(repeatItem)
            }

            let cancelItem = NSMenuItem(
                title: timer.isCompleted ? "Dismiss" : "Cancel",
                action: #selector(cancelTimer(_:)),
                keyEquivalent: ""
            )
            cancelItem.target = self
            cancelItem.representedObject = timer.id.uuidString
            menu.addItem(cancelItem)
            menu.addItem(.separator())
        }

        if !menu.items.isEmpty {
            menu.removeItem(at: menu.items.count - 1)
        }
        return menu
    }

    /// Builds the Pomodoro dropdown menu.
    private func makePomodoroMenu(session: PomodoroSession) -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let titleItem = NSMenuItem(
            title: "\(session.currentBlock.menuTitle) \(formatSeconds(coordinator.pomodoroRemainingSeconds()))",
            action: nil,
            keyEquivalent: ""
        )
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let pauseItem = NSMenuItem(
            title: session.isPaused ? "Play" : "Pause",
            action: #selector(togglePomodoroPause),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        let skipItem = NSMenuItem(title: "Skip this block", action: #selector(skipPomodoro), keyEquivalent: "")
        skipItem.target = self
        menu.addItem(skipItem)

        let resetItem = NSMenuItem(title: "Reset", action: #selector(resetPomodoro), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        let stopItem = NSMenuItem(title: "Stop", action: #selector(stopPomodoro), keyEquivalent: "")
        stopItem.target = self
        menu.addItem(stopItem)

        return menu
    }

    /// Refreshes realtime menu titles before a menu opens.
    func menuWillOpen(_ menu: NSMenu) {
        syncStatusItems()
    }

    /// Toggles one timer pause state.
    @objc private func toggleTimerPause(_ sender: NSMenuItem) {
        guard let id = uuid(from: sender) else { return }
        coordinator.toggleTimerPause(id: id)
        syncStatusItems()
    }

    /// Cancels or dismisses one timer.
    @objc private func cancelTimer(_ sender: NSMenuItem) {
        guard let id = uuid(from: sender) else { return }
        alertCenter.stopAlertSound()
        coordinator.cancelTimer(id: id)
        syncStatusItems()
    }

    /// Repeats one completed timer.
    @objc private func repeatTimer(_ sender: NSMenuItem) {
        guard let id = uuid(from: sender) else { return }
        alertCenter.stopAlertSound()
        coordinator.repeatTimer(id: id)
        syncStatusItems()
    }

    /// Toggles Pomodoro pause state.
    @objc private func togglePomodoroPause() {
        alertCenter.stopAlertSound()
        coordinator.togglePomodoroPause()
        syncStatusItems()
    }

    /// Skips the current Pomodoro block.
    @objc private func skipPomodoro() {
        alertCenter.stopAlertSound()
        coordinator.skipPomodoroBlock()
        syncStatusItems()
    }

    /// Resets the current Pomodoro block.
    @objc private func resetPomodoro() {
        alertCenter.stopAlertSound()
        coordinator.resetPomodoroBlock()
        syncStatusItems()
    }

    /// Stops the active Pomodoro.
    @objc private func stopPomodoro() {
        alertCenter.stopAlertSound()
        coordinator.stopPomodoro()
        syncStatusItems()
    }

    /// Reads a UUID from a menu item's represented object.
    private func uuid(from item: NSMenuItem) -> UUID? {
        guard let rawValue = item.representedObject as? String else { return nil }
        return UUID(uuidString: rawValue)
    }

    /// Formats seconds as a menu-bar countdown.
    private func formatSeconds(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(ceil(seconds)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
