import AppKit
import SwiftUI

@MainActor
/// AppKit delegate that wires together the menu-bar app, input bridge, HUDs, and live log.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Menu-bar status item that owns the app menu.
    private var statusItem: NSStatusItem?
    /// Lazily created live-log window.
    private var logWindow: NSWindow?
    /// Lazily created app settings window.
    private var settingsWindow: NSWindow?
    /// Menu item used to reflect and toggle Timer HUD visibility.
    private var timerHUDMenuItem: NSMenuItem?
    /// Menu item used to reflect and toggle Excalidraw HUD visibility.
    private var excalidrawHUDMenuItem: NSMenuItem?
    /// In-memory diagnostics store displayed by the live log.
    private let activityLog = ActivityLogStore()
    /// Thread-safe HUD visibility mirror shared with listener code.
    private let hudVisibilityState = HUDVisibilityState()
    /// Thread-safe marker for HUDs opened by temporary testing controls.
    private let hudTestingState = HUDTestingState()
    /// Message bus for delivering backend inputs to visible HUD views.
    private let hudMessages = HUDMessageBus()
    /// Main-actor source of truth for HUD visibility and state.
    private lazy var hudStore = HUDStore(visibilityState: hudVisibilityState)
    /// Runtime owner for the single active HUD session.
    private lazy var hudController = HUDController(
        hudStore: hudStore,
        hudMessages: hudMessages,
        visibilityState: hudVisibilityState,
        testingState: hudTestingState
    )
    /// Temporary menu-bar HUD testing injection.
    private lazy var hudTestingController = HUDTestingController(hudController: hudController)
    /// Registry for HUD definitions and their background workers.
    private lazy var hudRegistry = HUDRegistry(hudController: hudController)
    /// Presenter responsible for creating and monitoring floating HUD windows.
    private lazy var hudPresenter = HUDWindowPresenter(
        hudStore: hudStore,
        hudMessages: hudMessages,
        definitions: hudRegistry.definitions,
        interactionReceiver: { [weak self] interaction in
            self?.swiftBridge.receive(interaction) ?? ListenerPipelineResult()
        }
    )
    /// Input bridge that streams trackpad snapshots, runs listeners, and emits backend events.
    private lazy var swiftBridge = SwiftBridge(
        activityLog: activityLog,
        listeners: [
            TimerHUDInputListener(
                hudController: hudController
            ),
            ExcalidrawHUDInputListener(
                hudController: hudController,
                modeState: hudRegistry.excalidrawModeState
            )
        ],
        eventReceiver: { [weak self] event in
            self?.handleBackendEvent(event)
        },
        snapshotReceiver: { [weak self] snapshot in
            self?.hudStore.updateTrackpad(snapshot)
        },
        shouldReceiveKeyboardInteraction: { [hudController] _ in
            hudController.isActive(TimerHUDDefinition.hudID) ||
            hudController.isActive(ExcalidrawHUDDefinition.hudID)
        }
    )

    /// Starts the input bridge, menu-bar UI, HUD presenter, and live log after launch.
    /// - Parameter notification: The AppKit launch notification.
    func applicationDidFinishLaunching(_ notification: Notification) {
        activityLog.record("drift launched.", category: .system)
        hudRegistry.applicationDidFinishLaunching()
        swiftBridge.start()
        configureMenuBar()
        hudPresenter.start()
        if shouldOpenLiveLogAtLaunch {
            openLiveLog()
        }
    }

    /// Stops input processing when the app is about to terminate.
    /// - Parameter notification: The AppKit termination notification.
    func applicationWillTerminate(_ notification: Notification) {
        swiftBridge.stop()
        hudRegistry.applicationWillTerminate()
    }

    /// Builds the menu-bar status item and app menu.
    private func configureMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        print(Bundle.main.bundleURL.path)
        if let url = Bundle.main.url(
                forResource: "logo-accent-white-transparent",
                withExtension: "png",
            ),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 20, height: 20)
            image.isTemplate = true
            item.button?.image = image
        } else {
            item.button?.title = "drift"
        }
        let menu = NSMenu()
        menu.delegate = self
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        let liveLogItem = NSMenuItem(title: "Open Live Log", action: #selector(openLiveLogFromMenu), keyEquivalent: "l")
        liveLogItem.target = self
        menu.addItem(liveLogItem)
        menu.addItem(.separator())
        let hudsMenu = NSMenu()
        let timerItem = NSMenuItem(title: "Timer HUD", action: #selector(toggleTimerHUD), keyEquivalent: "t")
        timerItem.target = self
        hudsMenu.addItem(timerItem)
        let excalidrawItem = NSMenuItem(title: "Excalidraw HUD", action: #selector(toggleExcalidrawHUD), keyEquivalent: "e")
        excalidrawItem.target = self
        hudsMenu.addItem(excalidrawItem)
        let hudsItem = NSMenuItem(title: "HUDs", action: nil, keyEquivalent: "")
        hudsItem.submenu = hudsMenu
        menu.addItem(hudsItem)
        timerHUDMenuItem = timerItem
        excalidrawHUDMenuItem = excalidrawItem
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit drift", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
        updateHUDMenuState()
    }

    /// Opens the live log from the menu item action.
    @objc private func openLiveLogFromMenu() {
        openLiveLog()
    }

    /// Opens the app settings window from the menu bar.
    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    /// Refreshes menu item state immediately before the menu opens.
    /// - Parameter menu: The menu that is about to open.
    func menuWillOpen(_ menu: NSMenu) {
        updateHUDMenuState()
    }

    /// Toggles Timer HUD visibility from the menu bar.
    @objc private func toggleTimerHUD() {
        let hudID = TimerHUDDefinition.hudID
        let isActive = hudController.isActive(hudID)
        let isActiveAfterToggle = hudTestingController.toggle(hudID)
        activityLog.record("\(isActive ? "Closed" : "Opened") Timer HUD from the menu bar.", category: .system)
        if isActiveAfterToggle {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        updateHUDMenuState()
    }

    /// Toggles Excalidraw HUD visibility from the menu bar.
    @objc private func toggleExcalidrawHUD() {
        let hudID = ExcalidrawHUDDefinition.hudID
        let isActive = hudController.isActive(hudID)
        let isActiveAfterToggle = hudTestingController.toggle(hudID)
        activityLog.record("\(isActive ? "Closed" : "Opened") Excalidraw HUD from the menu bar.", category: .system)
        if isActiveAfterToggle {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        updateHUDMenuState()
    }

    /// Observes completed listener events for logging, haptics, and menu synchronization.
    /// - Parameter event: The event emitted by the input bridge.
    private func handleBackendEvent(_ event: BackendEvent) {
        switch event {
        case .timerHUDDidOpen:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            activityLog.record("Opened Timer HUD from the bottom-left swipe.", category: .action)
            updateHUDMenuState()
        case .timerHUDDidClose(let reason):
            let reasonText = switch reason {
            case .clickOutside: "an outside click"
            case .escape: "Escape"
            }
            activityLog.record("Closed Timer HUD from \(reasonText).", category: .action)
            updateHUDMenuState()
        case .timerHUDDidReceiveInput(let input):
            activityLog.record("Timer HUD received \(input.kind.displayName).", category: .action)
        case .excalidrawHUDDidOpen:
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            activityLog.record("Opened Excalidraw HUD from the top-edge swipe.", category: .action)
            updateHUDMenuState()
        case .excalidrawHUDDidClose(let reason):
            let reasonText = switch reason {
            case .clickOutside: "an outside click"
            case .escape: "Escape"
            case .commandW: "Command-W"
            }
            activityLog.record("Closed Excalidraw HUD from \(reasonText).", category: .action)
            updateHUDMenuState()
        case .excalidrawHUDDidReceiveInput(let input):
            let inputText = switch input.kind {
            case .moveLeft: "move left"
            case .moveRight: "move right"
            case .execute: "execute"
            }
            activityLog.record("Excalidraw HUD received \(inputText).", category: .action)
        }
    }

    /// Synchronizes the Timer HUD menu item title and checkmark with current HUD state.
    private func updateHUDMenuState() {
        let isTimerActive = hudController.isActive(TimerHUDDefinition.hudID)
        timerHUDMenuItem?.state = isTimerActive ? .on : .off
        timerHUDMenuItem?.title = isTimerActive ? "Hide Timer HUD" : "Show Timer HUD"

        let isExcalidrawActive = hudController.isActive(ExcalidrawHUDDefinition.hudID)
        excalidrawHUDMenuItem?.state = isExcalidrawActive ? .on : .off
        excalidrawHUDMenuItem?.title = isExcalidrawActive ? "Hide Excalidraw HUD" : "Show Excalidraw HUD"
    }

    /// Creates or focuses the live-log window.
    private func openLiveLog() {
        if logWindow == nil {
            let view = LoggingView(activityLog: activityLog, hudStore: hudStore)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "drift Live Log"
            window.setContentSize(NSSize(width: 760, height: 560))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.center()
            logWindow = window
        }
        logWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Creates or focuses the app settings window.
    private func openSettings() {
        if settingsWindow == nil {
            let timerWorker = hudRegistry.timerWorker
            let view = SettingsView(
                documents: hudRegistry.excalidrawWorker.documents,
                timerPreferences: timerWorker.timerPreferences,
                pomodoroPreferences: timerWorker.pomodoroPreferences,
                timerWorker: timerWorker
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "drift Settings"
            window.setContentSize(NSSize(width: 720, height: 480))
            window.minSize = NSSize(width: 680, height: 440)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Whether the live log should open automatically after launch.
    private var shouldOpenLiveLogAtLaunch: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: AppPreferenceKey.openLiveLogAtLaunch) != nil else {
            return true
        }
        return defaults.bool(forKey: AppPreferenceKey.openLiveLogAtLaunch)
    }

    /// Terminates the AppKit application.
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
