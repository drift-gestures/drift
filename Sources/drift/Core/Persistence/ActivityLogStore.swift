import Combine
import Foundation

/// In-memory testing console state that observes backend activity without owning recognition or UI.
@MainActor
final class ActivityLogStore: ObservableObject {
    /// Top-level categories used to group live-log entries.
    enum Category: String {
        /// App lifecycle and backend status messages.
        case system = "System"
        /// Raw or normalized input events.
        case input = "Input"
        /// Listener state transition messages.
        case listener = "Listener"
        /// Semantic app actions emitted by listeners.
        case action = "Action"
    }

    /// One row in the live activity log.
    struct Entry: Identifiable {
        /// Unique identity used by SwiftUI list rendering and scroll anchoring.
        let id = UUID()
        /// The time the entry was created.
        let timestamp = Date()
        /// The entry's grouping category.
        let category: Category
        /// The human-readable log message.
        let message: String
    }

    /// Newest-first activity entries displayed by `LoggingView`.
    @Published private(set) var entries: [Entry] = []
    /// The active backend name shown in the live state header.
    @Published private(set) var activeBackendName: InputBackendName = .inactive
    /// The latest backend status or permission message.
    @Published private(set) var backendMessage = "Not started"
    /// A compact description of the most recent input event.
    @Published private(set) var lastInputDescription = "Waiting for input"
    /// The most recent trackpad snapshot observed by the bridge.
    @Published private(set) var latestSnapshot: TrackpadSnapshot?

    /// Last time a snapshot summary was inserted into the log.
    private var lastSnapshotLogDate = Date.distantPast
    /// Last snapshot phase that was logged.
    private var lastSnapshotPhase: TrackpadPhase?
    /// Last snapshot finger count that was logged.
    private var lastSnapshotFingerCount = 0
    /// Last known status label for each listener type name.
    private var listenerStatuses: [String: String] = [:]
    /// Whether the previous pipeline result had an active interaction claim.
    private var wasInteractionClaimed = false

    /// Inserts a message into the activity log and trims the log to its retention limit.
    /// - Parameters:
    ///   - message: The text to display.
    ///   - category: The category used for grouping and row color.
    func record(_ message: String, category: Category) {
        entries.insert(Entry(category: category, message: message), at: 0)
        if entries.count > 300 {
            entries.removeLast(entries.count - 300)
        }
    }

    /// Removes all activity entries while preserving current backend and live-state values.
    func clear() {
        entries.removeAll()
    }

    /// Updates backend status and records a system log entry.
    /// - Parameters:
    ///   - name: The backend currently active or inactive.
    ///   - message: Additional status text, usually including permission or listener details.
    func setBackend(_ name: InputBackendName, message: String) {
        activeBackendName = name
        backendMessage = message
        record("Backend: \(name.rawValue). \(message)", category: .system)
    }

    /// Records a received trackpad snapshot and throttles verbose frame logging.
    /// - Parameter snapshot: The latest trackpad snapshot from the input bridge.
    func record(snapshot: TrackpadSnapshot) {
        latestSnapshot = snapshot
        lastInputDescription = "Trackpad frame \(snapshot.frame)"
        let now = Date()
        let phaseChanged = snapshot.phase != lastSnapshotPhase
        let fingerCountChanged = snapshot.fingerCount != lastSnapshotFingerCount
        guard phaseChanged || fingerCountChanged || now.timeIntervalSince(lastSnapshotLogDate) >= 0.35 else { return }

        lastSnapshotLogDate = now
        lastSnapshotPhase = snapshot.phase
        lastSnapshotFingerCount = snapshot.fingerCount
        let degrees = snapshot.rotation * 180 / .pi
        record(
            String(
                format: "Frame %d %@: %d contacts, center (%.3f, %.3f), scale %.3f, rotation %.1f°.",
                snapshot.frame,
                snapshot.phase.rawValue,
                snapshot.fingerCount,
                snapshot.center.x,
                snapshot.center.y,
                snapshot.scale,
                degrees
            ),
            category: .input
        )
    }

    /// Records listener state changes and interaction-claim transitions.
    /// - Parameters:
    ///   - activities: Listener activity snapshots returned by the pipeline.
    ///   - didClaimInteraction: Whether a listener owns the current interaction after processing.
    func record(activities: [ListenerActivity], didClaimInteraction: Bool) {
        for activity in activities {
            let status = activity.status.label
            guard listenerStatuses[activity.listenerName] != status else { continue }
            listenerStatuses[activity.listenerName] = status
            record("\(activity.listenerName): \(status).", category: .listener)
        }
        if didClaimInteraction != wasInteractionClaimed {
            wasInteractionClaimed = didClaimInteraction
            record(
                didClaimInteraction ? "A listener claimed the interaction." : "The interaction claim ended.",
                category: .listener
            )
        }
    }
}
