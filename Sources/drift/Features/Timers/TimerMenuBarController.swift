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
        if let menu = item.menu,
           timerMenuMatchesCurrentTimers(menu) {
            updateTimerMenu(menu)
        } else {
            item.menu = makeTimerMenu()
        }
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
        if let menu = item.menu {
            updatePomodoroMenu(menu, session: session)
        } else {
            item.menu = makePomodoroMenu(session: session)
        }
    }

    /// Title shown in the plain timer status item.
    private var timerStatusTitle: String {
        if let seconds = coordinator.nextTimerRemainingSeconds() {
            let title = formatSeconds(seconds)
            let unfinishedTimerCount = coordinator.timers.filter { !$0.isCompleted }.count
            guard unfinishedTimerCount > 1 else { return title }
            return "\(title) (\(unfinishedTimerCount))"
        }
        return coordinator.timers.contains { $0.isCompleted } ? "Done" : ""
    }

    /// Builds the timer dropdown menu.
    private func makeTimerMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        for timer in coordinator.timers {
            let remaining = coordinator.remainingSeconds(for: timer)
            let title = timer.isCompleted ? "Timer finished" : "Timer \(formatSeconds(remaining))"
            let titleItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            titleItem.identifier = timerTitleIdentifier(for: timer.id)
            titleItem.isEnabled = false
            menu.addItem(titleItem)

            let primaryItem = NSMenuItem(
                title: timerPrimaryActionTitle(for: timer),
                action: timerPrimaryAction(for: timer),
                keyEquivalent: ""
            )
            primaryItem.identifier = timerPrimaryActionIdentifier(for: timer.id)
            primaryItem.target = self
            primaryItem.representedObject = timer.id.uuidString
            menu.addItem(primaryItem)

            let cancelItem = NSMenuItem(
                title: timer.isCompleted ? "Dismiss" : "Cancel",
                action: #selector(cancelTimer(_:)),
                keyEquivalent: ""
            )
            cancelItem.identifier = timerCancelActionIdentifier(for: timer.id)
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
        titleItem.identifier = Self.pomodoroTitleIdentifier
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        let pauseItem = NSMenuItem(
            title: session.isPaused ? "Play" : "Pause",
            action: #selector(togglePomodoroPause),
            keyEquivalent: ""
        )
        pauseItem.identifier = Self.pomodoroPauseIdentifier
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

    /// Updates an existing timer menu while preserving the displayed menu object.
    /// - Parameter menu: Timer menu to update.
    private func updateTimerMenu(_ menu: NSMenu) {
        for timer in coordinator.timers {
            if let titleItem = menu.item(withIdentifier: timerTitleIdentifier(for: timer.id)) {
                let remaining = coordinator.remainingSeconds(for: timer)
                titleItem.title = timer.isCompleted ? "Timer finished" : "Timer \(formatSeconds(remaining))"
            }
            if let primaryItem = menu.item(withIdentifier: timerPrimaryActionIdentifier(for: timer.id)) {
                primaryItem.title = timerPrimaryActionTitle(for: timer)
                primaryItem.action = timerPrimaryAction(for: timer)
            }
            if let cancelItem = menu.item(withIdentifier: timerCancelActionIdentifier(for: timer.id)) {
                cancelItem.title = timer.isCompleted ? "Dismiss" : "Cancel"
            }
        }
    }

    /// Checks whether an existing timer menu still represents the current timer identities.
    /// - Parameter menu: Timer menu to inspect.
    /// - Returns: `true` when item titles can be updated in place.
    private func timerMenuMatchesCurrentTimers(_ menu: NSMenu) -> Bool {
        let menuIDs = Set(menu.items.compactMap(timerID(fromTitleIdentifier:)))
        let currentIDs = Set(coordinator.timers.map(\.id))
        return menuIDs == currentIDs
    }

    /// Updates an existing Pomodoro menu while preserving the displayed menu object.
    /// - Parameters:
    ///   - menu: Pomodoro menu to update.
    ///   - session: Current Pomodoro session.
    private func updatePomodoroMenu(_ menu: NSMenu, session: PomodoroSession) {
        if let titleItem = menu.item(withIdentifier: Self.pomodoroTitleIdentifier) {
            titleItem.title = "\(session.currentBlock.menuTitle) \(formatSeconds(coordinator.pomodoroRemainingSeconds()))"
        }
        if let pauseItem = menu.item(withIdentifier: Self.pomodoroPauseIdentifier) {
            pauseItem.title = session.isPaused ? "Play" : "Pause"
        }
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

    /// Primary action title for a timer.
    /// - Parameter timer: Timer represented by the menu item.
    /// - Returns: User-facing action title.
    private func timerPrimaryActionTitle(for timer: BackgroundTimerSession) -> String {
        if timer.isCompleted { return "Repeat" }
        return timer.isPaused ? "Play" : "Pause"
    }

    /// Primary action selector for a timer.
    /// - Parameter timer: Timer represented by the menu item.
    /// - Returns: Action selector to install on the menu item.
    private func timerPrimaryAction(for timer: BackgroundTimerSession) -> Selector {
        timer.isCompleted ? #selector(repeatTimer(_:)) : #selector(toggleTimerPause(_:))
    }

    /// Identifier for a timer title item.
    private func timerTitleIdentifier(for id: UUID) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("timer-title-\(id.uuidString)")
    }

    /// Identifier for a timer primary action item.
    private func timerPrimaryActionIdentifier(for id: UUID) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("timer-primary-\(id.uuidString)")
    }

    /// Identifier for a timer cancel action item.
    private func timerCancelActionIdentifier(for id: UUID) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("timer-cancel-\(id.uuidString)")
    }

    /// Reads a timer ID from a timer title item identifier.
    private func timerID(fromTitleIdentifier item: NSMenuItem) -> UUID? {
        guard let rawValue = item.identifier?.rawValue,
              rawValue.hasPrefix("timer-title-")
        else {
            return nil
        }
        return UUID(uuidString: String(rawValue.dropFirst("timer-title-".count)))
    }

    /// Identifier for the Pomodoro title item.
    private static let pomodoroTitleIdentifier = NSUserInterfaceItemIdentifier("pomodoro-title")
    /// Identifier for the Pomodoro pause/play item.
    private static let pomodoroPauseIdentifier = NSUserInterfaceItemIdentifier("pomodoro-pause")
}

private extension NSMenu {
    /// Finds the first menu item with a matching identifier.
    /// - Parameter identifier: Item identifier to find.
    /// - Returns: Matching menu item, if present.
    func item(withIdentifier identifier: NSUserInterfaceItemIdentifier) -> NSMenuItem? {
        items.first { $0.identifier == identifier }
    }
}
