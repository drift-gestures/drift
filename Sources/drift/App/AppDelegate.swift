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
    /// Message bus for delivering backend inputs to visible HUD views.
    private let hudMessages = HUDMessageBus()
    /// Main-actor source of truth for HUD visibility and state.
    private lazy var hudStore = HUDStore(visibilityState: hudVisibilityState)
    /// Presenter responsible for creating and monitoring floating HUD windows.
    private lazy var hudPresenter = HUDWindowPresenter(
        hudStore: hudStore,
        hudMessages: hudMessages,
        definitions: [AnyHUDDefinition(TimerHUDDefinition())],
        interactionReceiver: { [weak self] interaction in
            self?.swiftBridge.receive(interaction)
        }
    )
    /// Input bridge that streams trackpad snapshots, runs listeners, and emits backend events.
    private lazy var swiftBridge = SwiftBridge(
        activityLog: activityLog,
        listeners: [
            TimerHUDInputListener(hudVisibilityState: hudVisibilityState)
        ],
        eventReceiver: { [weak self] event in
            self?.handleBackendEvent(event)
        },
        snapshotReceiver: { [weak self] snapshot in
            self?.hudStore.updateTrackpad(snapshot)
        },
        shouldReceiveKeyboardInteraction: { [hudVisibilityState] keyPress in
            keyPress.keyCode == KeyboardKey.escape &&
                hudVisibilityState.isActive(TimerHUDDefinition.hudID)
        }
    )

    /// Starts the input bridge, menu-bar UI, HUD presenter, and live log after launch.
    /// - Parameter notification: The AppKit launch notification.
    func applicationDidFinishLaunching(_ notification: Notification) {
        activityLog.record("drift launched with no registered gesture listeners.", category: .system)
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
        hudStore.toggle(TimerHUDDefinition.hudID)
        let isActive = hudStore.activeHUDs.contains(TimerHUDDefinition.hudID)
        activityLog.record("\(isActive ? "Opened" : "Closed") Timer HUD from the menu bar.", category: .system)
        updateHUDMenuState()
    }

    /// Applies semantic backend events to HUD state and messages.
    /// - Parameter event: The event emitted by the input bridge.
    private func handleBackendEvent(_ event: BackendEvent) {
        switch event {
        case .timerHUDActivationRequested:
            hudStore.activate(TimerHUDDefinition.hudID)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            activityLog.record("Opened Timer HUD from the bottom-left swipe.", category: .action)
            updateHUDMenuState()
        case .timerHUDCloseRequested:
            hudStore.deactivate(TimerHUDDefinition.hudID)
            activityLog.record("Closed Timer HUD from an outside click.", category: .action)
            updateHUDMenuState()
        case .timerHUDInput(let input):
            hudMessages.send(.timerInput(input), to: TimerHUDDefinition.hudID)
        }
    }

    /// Synchronizes the Timer HUD menu item title and checkmark with current HUD state.
    private func updateHUDMenuState() {
        let isActive = hudStore.activeHUDs.contains(TimerHUDDefinition.hudID)
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
