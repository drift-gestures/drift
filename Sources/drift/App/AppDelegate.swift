import AppKit
import SwiftUI

@MainActor
/// AppKit delegate that wires together the menu-bar app, input bridge, HUDs, and live log.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Menu-bar status item that owns the app menu.
    private var statusItem: NSStatusItem?
    /// Lazily created live-log window.
    private var logWindow: NSWindow?
    /// Menu item used to reflect and toggle Timer HUD visibility.
    private var timerHUDMenuItem: NSMenuItem?
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
            )
        ],
        eventReceiver: { [weak self] event in
            self?.handleBackendEvent(event)
        },
        snapshotReceiver: { [weak self] snapshot in
            self?.hudStore.updateTrackpad(snapshot)
        },
        shouldReceiveKeyboardInteraction: { [hudController] _ in
            hudController.isActive(TimerHUDDefinition.hudID)
        }
    )

    /// Starts the input bridge, menu-bar UI, HUD presenter, and live log after launch.
    /// - Parameter notification: The AppKit launch notification.
    func applicationDidFinishLaunching(_ notification: Notification) {
        activityLog.record("drift launched with no registered gesture listeners.", category: .system)
        hudRegistry.applicationDidFinishLaunching()
        swiftBridge.start()
        configureMenuBar()
        hudPresenter.start()
        openLiveLog()
    }

    /// Stops input processing when the app is about to terminate.
    /// - Parameter notification: The AppKit termination notification.
    func applicationWillTerminate(_ notification: Notification) {
        swiftBridge.stop()
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
        let liveLogItem = NSMenuItem(title: "Open Live Log", action: #selector(openLiveLogFromMenu), keyEquivalent: ",")
        liveLogItem.target = self
        menu.addItem(liveLogItem)
        menu.addItem(.separator())
        let hudsMenu = NSMenu()
        let timerItem = NSMenuItem(title: "Timer HUD", action: #selector(toggleTimerHUD), keyEquivalent: "t")
        timerItem.target = self
        hudsMenu.addItem(timerItem)
        let hudsItem = NSMenuItem(title: "HUDs", action: nil, keyEquivalent: "")
        hudsItem.submenu = hudsMenu
        menu.addItem(hudsItem)
        timerHUDMenuItem = timerItem
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
        }
    }

    /// Synchronizes the Timer HUD menu item title and checkmark with current HUD state.
    private func updateHUDMenuState() {
        let isActive = hudController.isActive(TimerHUDDefinition.hudID)
        timerHUDMenuItem?.state = isActive ? .on : .off
        timerHUDMenuItem?.title = isActive ? "Hide Timer HUD" : "Show Timer HUD"
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

    /// Terminates the AppKit application.
    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
