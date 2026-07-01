import Foundation

/// Receives C snapshots, calls registered listeners in order, applies their suppression requests,
/// and forwards semantic events to the frontend.
final class SwiftBridge: @unchecked Sendable {
    private let activityLog: ActivityLogStore
    private let eventReceiver: @MainActor (BackendEvent) -> Void
    private let snapshotReceiver: @MainActor (TrackpadSnapshot) -> Void
    private let cBridge = CTrackpadBridge()
    private let listeners: ListenerPipeline
    private let listenerCount: Int
    private let suppressionController = EventSuppressionController()
    private let processingLock = NSLock()

    init(
        activityLog: ActivityLogStore,
        listeners: [any Listener],
        eventReceiver: @escaping @MainActor (BackendEvent) -> Void,
        snapshotReceiver: @escaping @MainActor (TrackpadSnapshot) -> Void
    ) {
        self.activityLog = activityLog
        self.listeners = ListenerPipeline(listeners: listeners)
        self.listenerCount = listeners.count
        self.eventReceiver = eventReceiver
        self.snapshotReceiver = snapshotReceiver
    }

    @MainActor
    func start() {
        let suppressionAvailable = suppressionController.start()
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

    func stop() {
        processingLock.lock()
        suppressionController.update([])
        processingLock.unlock()
        cBridge.stop()
        suppressionController.stop()
    }

    func receive(_ interaction: Interaction) {
        processingLock.lock()
        let result = listeners.process(interaction)
        suppressionController.update(result.suppressions)
        processingLock.unlock()

        Task { @MainActor in
            record(interaction)
            activityLog.record(
                activities: result.activities,
                didClaimInteraction: result.didClaimInteraction
            )
            result.events.forEach(eventReceiver)
        }
    }

    private func receive(_ snapshot: TrackpadSnapshot) {
        receive(.trackpadSnapshot(snapshot))
    }

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
        case .clickOutside(let click):
            activityLog.record(
                "Clicked outside \(click.hudID.rawValue) HUD.",
                category: .input
            )
        }
    }
}
