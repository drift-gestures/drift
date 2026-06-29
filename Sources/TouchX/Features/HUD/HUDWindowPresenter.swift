import AppKit
import Combine
import SwiftUI

@MainActor
final class HUDWindowPresenter {
    private let hudStore: HUDStore
    private let definitions: [HUDID: AnyHUDDefinition]
    private var windows: [HUDID: NSPanel] = [:]
    private var cancellable: AnyCancellable?

    init(hudStore: HUDStore, definitions: [AnyHUDDefinition]) {
        self.hudStore = hudStore
        self.definitions = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
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
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = CGRect(origin: .zero, size: definition.size)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
        panel.setFrame(frame, display: false)
        return panel
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
