import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var logWindow: NSWindow?
    private var timerHUDMenuItem: NSMenuItem?
    private let activityLog = ActivityLogStore()
    private let hudVisibilityState = HUDVisibilityState()
    private let hudMessages = HUDMessageBus()
    private lazy var hudStore = HUDStore(visibilityState: hudVisibilityState)
    private lazy var hudPresenter = HUDWindowPresenter(
        hudStore: hudStore,
        hudMessages: hudMessages,
        definitions: [AnyHUDDefinition(TimerHUDDefinition())],
        interactionReceiver: { [weak self] interaction in
            self?.swiftBridge.receive(interaction)
        }
    )
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        activityLog.record("drift launched with no registered gesture listeners.", category: .system)
        swiftBridge.start()
        configureMenuBar()
        hudPresenter.start()
        openLiveLog()
    }

    func applicationWillTerminate(_ notification: Notification) {
        swiftBridge.stop()
    }

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

    @objc private func openLiveLogFromMenu() {
        openLiveLog()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateHUDMenuState()
    }

    @objc private func toggleTimerHUD() {
        hudStore.toggle(TimerHUDDefinition.hudID)
        let isActive = hudStore.activeHUDs.contains(TimerHUDDefinition.hudID)
        activityLog.record("\(isActive ? "Opened" : "Closed") Timer HUD from the menu bar.", category: .system)
        updateHUDMenuState()
    }

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

    private func updateHUDMenuState() {
        let isActive = hudStore.activeHUDs.contains(TimerHUDDefinition.hudID)
        timerHUDMenuItem?.state = isActive ? .on : .off
        timerHUDMenuItem?.title = isActive ? "Hide Timer HUD" : "Show Timer HUD"
    }

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

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
