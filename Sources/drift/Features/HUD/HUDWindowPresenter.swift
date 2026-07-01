import AppKit
import Combine
import SwiftUI

@MainActor
/// Presents active HUD definitions as floating AppKit panels and routes outside interactions.
final class HUDWindowPresenter {
    /// Store that publishes the current active HUD set.
    private let hudStore: HUDStore
    /// Message bus injected into HUD SwiftUI content.
    private let hudMessages: HUDMessageBus
    /// Registered HUD definitions keyed by identifier.
    private let definitions: [HUDID: AnyHUDDefinition]
    /// Receiver used to send HUD-originated interactions back into the input pipeline.
    private let interactionReceiver: @MainActor (Interaction) -> Void
    /// Currently displayed HUD panels keyed by identifier.
    private var windows: [HUDID: NSPanel] = [:]
    /// Subscription to HUD visibility changes.
    private var cancellable: AnyCancellable?
    /// Local mouse monitor used to detect clicks outside HUD windows while drift is active.
    private var localClickMonitor: Any?
    /// Global mouse monitor used to detect clicks outside HUD windows while other apps are active.
    private var globalClickMonitor: Any?
    /// Local keyboard monitor used to route key presses to listeners.
    private var localKeyboardMonitor: Any?
    /// Global keyboard monitor used to route key presses while other apps are active.
    private var globalKeyboardMonitor: Any?

    /// Creates a HUD window presenter.
    /// - Parameters:
    ///   - hudStore: Store that owns visible HUD state.
    ///   - hudMessages: Message bus to inject into HUD content.
    ///   - definitions: HUD definitions available for presentation.
    ///   - interactionReceiver: Main-actor receiver for outside-click and keyboard interactions.
    init(
        hudStore: HUDStore,
        hudMessages: HUDMessageBus,
        definitions: [AnyHUDDefinition],
        interactionReceiver: @escaping @MainActor (Interaction) -> Void
    ) {
        self.hudStore = hudStore
        self.hudMessages = hudMessages
        self.definitions = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        self.interactionReceiver = interactionReceiver
    }

    /// Starts observing HUD visibility and synchronizes the initial window set.
    func start() {
        guard cancellable == nil else { return }
        cancellable = hudStore.$activeHUDs.sink { [weak self] activeHUDs in
            self?.syncWindows(activeHUDs: activeHUDs)
        }
        syncWindows(activeHUDs: hudStore.activeHUDs)
    }

    /// Creates missing windows, closes inactive windows, and updates event monitors.
    /// - Parameter activeHUDs: The HUD identifiers that should currently be visible.
    private func syncWindows(activeHUDs: Set<HUDID>) {
        for id in activeHUDs where windows[id] == nil {
            guard let definition = definitions[id] else { continue }
            let window = makeWindow(for: definition)
            windows[id] = window
            window.orderFrontRegardless()
        }

        for id in Array(windows.keys) where !activeHUDs.contains(id) {
            windows[id]?.close()
            windows[id] = nil
        }

        updateInteractionMonitoring()
    }

    /// Builds an AppKit panel for one HUD definition.
    /// - Parameter definition: The HUD definition to render.
    /// - Returns: A configured, borderless floating panel.
    private func makeWindow(for definition: AnyHUDDefinition) -> NSPanel {
        let screenFrame = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let layoutContext = HUDLayoutContext(
            mousePosition: NSEvent.mouseLocation,
            screenFrame: screenFrame,
            trackpadState: hudStore.trackpadState
        )
        let hudContext = HUDContext(
            layout: layoutContext,
            state: hudStore.customStates[definition.id.rawValue] ?? HUDState()
        )
        let origin = definition.position(in: layoutContext)
        let frame = CGRect(origin: origin, size: definition.size)
        let rootView = definition.content(context: hudContext)
            .environmentObject(hudStore)
            .environmentObject(hudMessages)
            .frame(width: definition.size.width, height: definition.size.height)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: definition.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.setFrame(frame, display: false)
        return panel
    }

    /// Starts or stops interaction monitoring based on whether any HUD windows are visible.
    private func updateInteractionMonitoring() {
        if windows.isEmpty {
            stopInteractionMonitoring()
        } else {
            startInteractionMonitoringIfNeeded()
        }
    }

    /// Installs mouse and keyboard monitors if they are not already active.
    private func startInteractionMonitoringIfNeeded() {
        guard localClickMonitor == nil,
              globalClickMonitor == nil,
              localKeyboardMonitor == nil,
              globalKeyboardMonitor == nil
        else {
            return
        }

        let mouseDownMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseDownMask) { [weak self] event in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleMouseDown(at: location)
            }
            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseDownMask) { [weak self] _ in
            let location = NSEvent.mouseLocation
            Task { @MainActor [weak self] in
                self?.handleMouseDown(at: location)
            }
        }

        localKeyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyPress = KeyboardPressInteraction(event: event)
            Task { @MainActor [weak self] in
                self?.interactionReceiver(.keyboardPress(keyPress))
            }
            return keyPress.keyCode == KeyboardKey.escape ? nil : event
        }

        globalKeyboardMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyPress = KeyboardPressInteraction(event: event)
            Task { @MainActor [weak self] in
                self?.interactionReceiver(.keyboardPress(keyPress))
            }
        }
    }

    /// Removes all installed mouse and keyboard monitors.
    private func stopInteractionMonitoring() {
        if let localClickMonitor {
            NSEvent.removeMonitor(localClickMonitor)
            self.localClickMonitor = nil
        }

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }

        if let localKeyboardMonitor {
            NSEvent.removeMonitor(localKeyboardMonitor)
            self.localKeyboardMonitor = nil
        }

        if let globalKeyboardMonitor {
            NSEvent.removeMonitor(globalKeyboardMonitor)
            self.globalKeyboardMonitor = nil
        }
    }

    /// Sends click-outside interactions for every visible HUD whose frame does not contain the click.
    /// - Parameter location: The click location in screen coordinates.
    private func handleMouseDown(at location: CGPoint) {
        for (id, window) in windows where !window.frame.contains(location) {
            interactionReceiver(
                .clickOutside(ClickOutsideInteraction(hudID: id, screenLocation: location))
            )
        }
    }
}

/// Type-erased wrapper around concrete HUD definitions.
struct AnyHUDDefinition {
    /// Identifier of the wrapped HUD definition.
    let id: HUDID
    /// Fixed window size of the wrapped HUD definition.
    let size: CGSize
    /// Closure used to compute a HUD window origin.
    private let positionProvider: (HUDLayoutContext) -> CGPoint
    /// Closure used to build type-erased HUD content.
    private let contentProvider: @MainActor (HUDContext) -> AnyView

    /// Wraps a concrete HUD definition.
    /// - Parameter definition: The concrete HUD definition to erase.
    @MainActor
    init<Definition: HudDefinition>(_ definition: Definition) {
        id = definition.id
        size = definition.size
        positionProvider = { context in definition.position(in: context) }
        contentProvider = { context in AnyView(definition.content(context: context)) }
    }

    /// Computes the wrapped HUD's window origin.
    /// - Parameter context: Layout context for the current presentation pass.
    /// - Returns: The HUD window origin.
    func position(in context: HUDLayoutContext) -> CGPoint {
        positionProvider(context)
    }

    /// Builds the wrapped HUD content as `AnyView`.
    /// - Parameter context: Render context for the HUD.
    /// - Returns: Type-erased HUD content.
    @MainActor
    func content(context: HUDContext) -> AnyView {
        contentProvider(context)
    }
}

private extension KeyboardPressInteraction {
    /// Creates a normalized keyboard interaction from an AppKit event.
    /// - Parameter event: The AppKit key-down event to translate.
    init(event: NSEvent) {
        var modifiers = Set<KeyboardModifier>()
        let flags = event.modifierFlags

        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.capsLock) {
            modifiers.insert(.capsLock)
        }
        if flags.contains(.function) {
            modifiers.insert(.function)
        }

        self.init(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            modifiers: modifiers
        )
    }
}
