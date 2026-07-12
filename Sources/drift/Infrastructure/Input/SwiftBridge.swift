import Foundation

/// Receives C snapshots, calls registered listeners in order, applies their suppression requests,
/// and forwards semantic events to the frontend.
final class SwiftBridge: @unchecked Sendable {
    /// Main-actor diagnostics store updated after each processed interaction.
    private let activityLog: ActivityLogStore
    /// Main-actor receiver for semantic listener events.
    private let eventReceiver: @MainActor (BackendEvent) -> Void
    /// Main-actor receiver for snapshots that should update HUD layout state.
    private let snapshotReceiver: @MainActor (TrackpadSnapshot) -> Void
    /// Predicate that determines whether global keyboard input should be forwarded to listeners.
    private let shouldReceiveKeyboardInteraction: (KeyboardPressInteraction) -> Bool
    /// Shared activation-key state used to gate basic and advanced gesture listeners.
    private let customGestureModeState: CustomGestureModeState?
    /// Main-actor receiver that presents runtime advanced-gesture listening state.
    private let advancedGestureModeReceiver: @MainActor (Bool) -> Void
    /// Bridge that loads and streams private multitouch snapshots.
    private let cBridge = CTrackpadBridge()
    /// Ordered listener pipeline used to classify interactions.
    private let listeners: ListenerPipeline
    /// Number of listeners registered at startup, used only for status text.
    private let listenerCount: Int
    /// Controller that applies listener suppression requests to foreground-app events.
    private let suppressionController = EventSuppressionController()
    /// Serializes listener processing and suppression updates across callback sources.
    private let processingLock = NSLock()

    /// Creates the Swift-side input bridge.
    /// - Parameters:
    ///   - activityLog: Store that receives status and interaction diagnostics.
    ///   - listeners: Ordered gesture listeners to evaluate.
    ///   - eventReceiver: Main-actor receiver for semantic backend events.
    ///   - snapshotReceiver: Main-actor receiver for raw snapshots.
    ///   - shouldReceiveKeyboardInteraction: Predicate for forwarding global keyboard events.
    init(
        activityLog: ActivityLogStore,
        listeners: [any Listener],
        customGestureModeState: CustomGestureModeState? = nil,
        advancedGestureModeReceiver: @escaping @MainActor (Bool) -> Void = { _ in },
        eventReceiver: @escaping @MainActor (BackendEvent) -> Void,
        snapshotReceiver: @escaping @MainActor (TrackpadSnapshot) -> Void,
        shouldReceiveKeyboardInteraction: @escaping (KeyboardPressInteraction) -> Bool = { _ in false }
    ) {
        self.activityLog = activityLog
        self.listeners = ListenerPipeline(
            listeners: listeners,
            isAdvancedGestureModeActive: { customGestureModeState?.isAdvancedModeActive ?? false }
        )
        self.listenerCount = listeners.count
        self.customGestureModeState = customGestureModeState
        self.advancedGestureModeReceiver = advancedGestureModeReceiver
        self.eventReceiver = eventReceiver
        self.snapshotReceiver = snapshotReceiver
        self.shouldReceiveKeyboardInteraction = shouldReceiveKeyboardInteraction
    }

    /// Starts foreground-event suppression and the private multitouch bridge.
    @MainActor
    func start() {
        let suppressionAvailable = suppressionController.start(
            keyboardInteractionReceiver: { [weak self] keyPress in
                self?.receive(.keyboardPress(keyPress)).suppressions ?? []
            },
            shouldReceiveKeyboardInteraction: shouldReceiveKeyboardInteraction,
            modifierStateReceiver: { [weak self] modifierState in
                self?.customGestureModeState?.update(modifiers: modifierState.modifiers)
                let isActive = self?.customGestureModeState?.isAdvancedModeActive ?? false
                Task { @MainActor [weak self] in
                    self?.advancedGestureModeReceiver(isActive)
                }
                _ = self?.receive(.modifierStateChanged(modifierState))
            }
        )
        let suppressionStatus = suppressionAvailable
            ? "Foreground-event suppression is available."
            : "Foreground-event suppression is unavailable; grant Accessibility/Input Monitoring if a listener requests it."
        let listenerStatus = listenerCount == 0
            ? "No gesture listeners are registered."
            : "\(listenerCount) gesture listener\(listenerCount == 1 ? "" : "s") registered."

        if cBridge.start(snapshotHandler: receive(_:)) {
            activityLog.setBackend(
                .enhanced,
                message: "\(cBridge.statusMessage). \(suppressionStatus) \(listenerStatus)"
            )
        } else {
            activityLog.setBackend(
                .inactive,
                message: "\(cBridge.statusMessage). \(suppressionStatus)"
            )
        }
    }

    /// Stops snapshot delivery and event suppression.
    func stop() {
        processingLock.lock()
        suppressionController.update([])
        processingLock.unlock()
        cBridge.stop()
        suppressionController.stop()
    }

    /// Processes one normalized interaction through listeners and applies the resulting effects.
    /// - Parameter interaction: The interaction received from the bridge or HUD window layer.
    /// - Returns: The pipeline result, primarily used by keyboard suppression callbacks.
    @discardableResult
    func receive(_ interaction: Interaction) -> ListenerPipelineResult {
        processingLock.lock()
        let result = listeners.process(interaction)
        suppressionController.update(persistentSuppressions(from: result.suppressions, for: interaction))
        processingLock.unlock()

        Task { @MainActor in
            record(interaction)
            activityLog.record(
                activities: result.activities,
                didClaimInteraction: result.didClaimInteraction
            )
            result.events.forEach(eventReceiver)
        }

        return result
    }

    /// Convenience receiver used as the C bridge snapshot callback.
    /// - Parameter snapshot: The snapshot received from the private multitouch bridge.
    private func receive(_ snapshot: TrackpadSnapshot) {
        receive(.trackpadSnapshot(snapshot))
    }

    /// Removes one-shot key suppressions after keyboard processing while preserving other requests.
    /// - Parameters:
    ///   - suppressions: Suppressions returned by the listener pipeline.
    ///   - interaction: The interaction that produced those suppressions.
    /// - Returns: Suppressions that should remain installed after this interaction.
    private func persistentSuppressions(
        from suppressions: Set<SuppressionRequest>,
        for interaction: Interaction
    ) -> Set<SuppressionRequest> {
        guard case .keyboardPress = interaction else { return suppressions }
        return suppressions.filter { request in
            guard case .keyPress = request else { return true }
            return false
        }
    }

    /// Records an interaction and forwards raw snapshots to HUD state on the main actor.
    /// - Parameter interaction: The processed interaction to describe in diagnostics.
    @MainActor
    private func record(_ interaction: Interaction) {
        switch interaction {
        case .trackpadSnapshot(let snapshot):
            activityLog.record(snapshot: snapshot)
            snapshotReceiver(snapshot)
        case .keyboardPress(let keyPress):
            let characters = keyPress.characters ?? "unprintable"
            activityLog.record(
                "Key press \(characters) (\(keyPress.keyCode)).",
                category: .input
            )
        case .modifierStateChanged(let modifierState):
            activityLog.record(
                "Modifier state changed (\(modifierState.modifiers.count) active).",
                category: .input
            )
        case .clickOutside(let click):
            activityLog.record(
                "Clicked outside \(click.hudID.rawValue) HUD.",
                category: .input
            )
        }
    }
}
