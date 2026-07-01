import AppKit
import Combine
import SwiftUI

@MainActor
final class HUDWindowPresenter {
    private let hudStore: HUDStore
    private let hudMessages: HUDMessageBus
    private let definitions: [HUDID: AnyHUDDefinition]
    private let interactionReceiver: @MainActor (Interaction) -> Void
    private var windows: [HUDID: NSPanel] = [:]
    private var cancellable: AnyCancellable?
    private var localClickMonitor: Any?
    private var globalClickMonitor: Any?
    private var localKeyboardMonitor: Any?
    private var globalKeyboardMonitor: Any?

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

    func start() {
        guard cancellable == nil else { return }
        cancellable = hudStore.$activeHUDs.sink { [weak self] activeHUDs in
            self?.syncWindows(activeHUDs: activeHUDs)
        }
        syncWindows(activeHUDs: hudStore.activeHUDs)
    }

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

    private func updateInteractionMonitoring() {
        if windows.isEmpty {
            stopInteractionMonitoring()
        } else {
            startInteractionMonitoringIfNeeded()
        }
    }

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

    private func handleMouseDown(at location: CGPoint) {
        for (id, window) in windows where !window.frame.contains(location) {
            interactionReceiver(
                .clickOutside(ClickOutsideInteraction(hudID: id, screenLocation: location))
            )
        }
    }
}

struct AnyHUDDefinition {
    let id: HUDID
    let size: CGSize
    private let positionProvider: (HUDLayoutContext) -> CGPoint
    private let contentProvider: @MainActor (HUDContext) -> AnyView

    @MainActor
    init<Definition: HudDefinition>(_ definition: Definition) {
        id = definition.id
        size = definition.size
        positionProvider = { context in definition.position(in: context) }
        contentProvider = { context in AnyView(definition.content(context: context)) }
    }

    func position(in context: HUDLayoutContext) -> CGPoint {
        positionProvider(context)
    }

    @MainActor
    func content(context: HUDContext) -> AnyView {
        contentProvider(context)
    }
}

private extension KeyboardPressInteraction {
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
