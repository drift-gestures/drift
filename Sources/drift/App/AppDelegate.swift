import AppKit
import SwiftUI

@MainActor
/// AppKit delegate that wires together the menu-bar app, input bridge, HUDs, and live log.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    /// Menu-bar status item that owns the app menu.
    private var statusItem: NSStatusItem?
    /// Lazily created live-log window.
    private var logWindow: NSWindow?
    /// Lazily created app settings window.
    private var settingsWindow: NSWindow?
    /// Standalone window that renders live trackpad contacts.
    private var trackpadMapWindow: NSWindow?
    /// Global pointer monitor used because the map window itself passes every event through.
    private var trackpadMapPointerMonitor: Any?
    /// Local counterpart that observes pointer movement over drift's own windows.
    private var trackpadMapLocalPointerMonitor: Any?
    /// State owned by the standalone virtual trackpad feature.
    private let trackpadMapStore = TrackpadMapStore()
    /// Whether the virtual trackpad is currently visible and should process snapshots.
    private var isTrackpadMapEnabled = false
    /// In-memory diagnostics store displayed by the live log.
    private let activityLog = ActivityLogStore()
    /// Main-actor state displayed by Settings for foreground-event suppression recovery.
    private let eventSuppressionStatus = EventSuppressionStatusModel()
    /// Device-local source of truth for all user-created gestures.
    private let customGestureStore = CustomGestureStore()
    /// Shared gate that makes the global advanced-gesture activation key exclusive.
    private lazy var customGestureModeState = CustomGestureModeState(store: customGestureStore)
    /// Shared exclusive gate used while Settings records or tests a gesture.
    private let customGestureCaptureState = CustomGestureCaptureState()
    /// Full-screen dismissal surface shown while runtime advanced gestures are active.
    private lazy var advancedGestureOverlayPresenter = AdvancedGestureOverlayPresenter { [weak self] in
        self?.customGestureModeState.suspendUntilModifiersReleased()
    }
    /// Main-actor recorder/tester fed by the same raw snapshots as normal listeners.
    private lazy var customGestureRecordingSession = CustomGestureRecordingSession(
        modeState: customGestureModeState,
        captureState: customGestureCaptureState
    )
    /// Observable Settings adapter for the device-local custom gesture library.
    private lazy var customGestureSettingsModel = CustomGestureSettingsModel(
        store: customGestureStore,
        recordingSession: customGestureRecordingSession
    )
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
            CustomGestureListener(
                store: customGestureStore,
                modeState: customGestureModeState,
                captureState: customGestureCaptureState,
                focusedApplicationBundleIdentifier: {
                    NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                }
            )
        ],
        customGestureModeState: customGestureModeState,
        advancedGestureModeReceiver: { [weak self] isActive in
            guard let self else { return }
            self.advancedGestureOverlayPresenter.setActive(
                isActive && !self.customGestureCaptureState.isActive
            )
        },
        suppressionStatusReceiver: { [eventSuppressionStatus] status in
            eventSuppressionStatus.update(status)
        },
        eventReceiver: { [weak self] event in
            self?.handleBackendEvent(event)
        },
        snapshotReceiver: { [weak self] snapshot in
            guard let self else { return }
            self.hudStore.updateTrackpad(snapshot)
            self.customGestureRecordingSession.receive(snapshot)
            if self.isTrackpadMapEnabled {
                self.trackpadMapStore.update(with: snapshot)
            }
        },
        shouldReceiveKeyboardInteraction: { _ in false }
    )

    /// Starts the input bridge, menu-bar UI, HUD presenter, and live log after launch.
    /// - Parameter notification: The AppKit launch notification.
    func applicationDidFinishLaunching(_ notification: Notification) {
        activityLog.record("drift launched.", category: .system)
        hudRegistry.applicationDidFinishLaunching()
        swiftBridge.start()
        configureMenuBar()
        hudPresenter.start()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        if UserDefaults.standard.bool(forKey: AppPreferenceKey.virtualTrackpadEnabled) {
            setVirtualTrackpadEnabled(true)
        }
        if shouldOpenLiveLogAtLaunch {
            openLiveLog()
        }
    }

    /// Stops input processing when the app is about to terminate.
    /// - Parameter notification: The AppKit termination notification.
    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        stopTrackpadMapPointerMonitoring()
        advancedGestureOverlayPresenter.setActive(false)
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
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit drift", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
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
    }

    /// Observes completed listener events for logging, haptics, and menu synchronization.
    /// - Parameter event: The event emitted by the input bridge.
    private func handleBackendEvent(_ event: BackendEvent) {
        switch event {
        case .customGestureRecognized(let id, let action, let source):
            CustomGestureActionPerformer.perform(action)
            if source == .basic {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
            activityLog.record("Performed custom gesture \(id).", category: .action)
        }
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
            let view = SettingsView(
                eventSuppressionStatus: eventSuppressionStatus,
                customGestures: customGestureSettingsModel,
                setVirtualTrackpadEnabled: { [weak self] enabled in
                    self?.setVirtualTrackpadEnabled(enabled)
                },
                retryEventSuppression: { [weak self] in
                    self?.swiftBridge.retryEventSuppression()
                }
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

    /// Opens or closes the standalone virtual trackpad window.
    private func setVirtualTrackpadEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: AppPreferenceKey.virtualTrackpadEnabled)
        isTrackpadMapEnabled = enabled
        trackpadMapStore.setEnabled(enabled)
        if enabled {
            if trackpadMapWindow == nil {
                let view = TrackpadMapView(store: trackpadMapStore)
                let window = NSWindow(contentViewController: NSHostingController(rootView: view))
                window.setContentSize(NSSize(width: 240, height: 150))
                window.styleMask = [.borderless]
                window.isReleasedWhenClosed = false
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
                window.ignoresMouseEvents = true
                window.level = .floating
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
                window.alphaValue = 0.72
                window.delegate = self
                trackpadMapWindow = window
            }
            positionTrackpadMapWindow()
            trackpadMapWindow?.orderFrontRegardless()
            startTrackpadMapPointerMonitoring()
        } else {
            stopTrackpadMapPointerMonitoring()
            trackpadMapWindow?.close()
            trackpadMapWindow = nil
        }
    }

    /// Anchors the mini map inside the bottom-right corner of the current main screen.
    private func positionTrackpadMapWindow() {
        guard let window = trackpadMapWindow, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleFrame = screen.visibleFrame
        window.setFrameOrigin(NSPoint(
            x: visibleFrame.maxX - window.frame.width - 16,
            y: visibleFrame.minY + 16
        ))
    }

    /// Watches pointer movement without making the pass-through window interactive.
    private func startTrackpadMapPointerMonitoring() {
        guard trackpadMapPointerMonitor == nil, trackpadMapLocalPointerMonitor == nil else { return }
        trackpadMapPointerMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateTrackpadMapTransparency()
            }
        }
        trackpadMapLocalPointerMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        ) { [weak self] event in
            self?.updateTrackpadMapTransparency()
            return event
        }
        updateTrackpadMapTransparency()
    }

    /// Stops global pointer observation when the map is disabled or the app terminates.
    private func stopTrackpadMapPointerMonitoring() {
        if let monitor = trackpadMapPointerMonitor {
            NSEvent.removeMonitor(monitor)
            trackpadMapPointerMonitor = nil
        }
        if let monitor = trackpadMapLocalPointerMonitor {
            NSEvent.removeMonitor(monitor)
            trackpadMapLocalPointerMonitor = nil
        }
    }

    /// Makes the mini map more see-through whenever the pointer is over its frame.
    private func updateTrackpadMapTransparency() {
        guard let window = trackpadMapWindow else { return }
        window.alphaValue = window.frame.contains(NSEvent.mouseLocation) ? 0.38 : 0.72
    }

    /// Keeps the overlay anchored after display geometry or menu-bar placement changes.
    @objc private func screenParametersDidChange() {
        positionTrackpadMapWindow()
    }

    /// Keeps the persisted setting synchronized when the user closes the map window directly.
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === trackpadMapWindow else { return }
        isTrackpadMapEnabled = false
        trackpadMapStore.setEnabled(false)
        stopTrackpadMapPointerMonitoring()
        UserDefaults.standard.set(false, forKey: AppPreferenceKey.virtualTrackpadEnabled)
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

/// Owns the screen-sized dismissal surface for the global advanced-gesture mode.
@MainActor
private final class AdvancedGestureOverlayPresenter {
    private var panels: [NSPanel] = []
    private let dismiss: () -> Void

    init(dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
    }

    func setActive(_ isActive: Bool) {
        guard isActive != !panels.isEmpty else { return }
        if isActive {
            panels = NSScreen.screens.map(makePanel(for:))
            panels.forEach { $0.orderFrontRegardless() }
        } else {
            panels.forEach { $0.close() }
            panels.removeAll()
        }
    }

    private func makePanel(for screen: NSScreen) -> NSPanel {
        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.contentView = AdvancedGestureOverlayHostingView(
            rootView: AdvancedGestureListeningOverlay { [weak self] in
                self?.dismissFromClick()
            }
        )
        return panel
    }

    private func dismissFromClick() {
        dismiss()
        setActive(false)
    }
}

/// Screen-filling visual feedback for the held advanced-gesture activation binding.
private struct AdvancedGestureListeningOverlay: View {
    let dismiss: () -> Void

    var body: some View {
        overlayContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(perform: dismiss)
            .ignoresSafeArea()
            .accessibilityLabel("Advanced gestures are being listened to. Click to stop listening.")
    }

    @ViewBuilder
    private var overlayContent: some View {
        VStack {
            Label("Listening for advanced gestures", systemImage: "hand.draw")
                .font(.title2)
                .foregroundStyle(.white)
                .padding()
                .background(Color.black, in: Capsule())
            Spacer()
        }
        .padding(.top, 50)
        .modifier(AdvancedGestureListeningSafeAreaPadding())
    }
}

private struct AdvancedGestureListeningSafeAreaPadding: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.safeAreaPadding(.top)
        } else {
            content
        }
    }
}

/// Ensures the first click reaches the clear overlay even while drift is inactive.
private final class AdvancedGestureOverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
