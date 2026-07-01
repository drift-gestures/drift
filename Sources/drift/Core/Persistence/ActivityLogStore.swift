import Combine
import Foundation

@MainActor
/// In-memory testing console state. It observes backend activity but does not own recognition or UI.
final class ActivityLogStore: ObservableObject {
    enum Category: String {
        case system = "System"
        case input = "Input"
        case listener = "Listener"
        case action = "Action"
    }

    struct Entry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let category: Category
        let message: String
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var activeBackendName: InputBackendName = .inactive
    @Published private(set) var backendMessage = "Not started"
    @Published private(set) var lastInputDescription = "Waiting for input"
    @Published private(set) var latestSnapshot: TrackpadSnapshot?

    private var lastSnapshotLogDate = Date.distantPast
    private var lastSnapshotPhase: TrackpadPhase?
    private var lastSnapshotFingerCount = 0
    private var listenerStatuses: [String: String] = [:]
    private var wasInteractionClaimed = false

    func record(_ message: String, category: Category) {
        entries.insert(Entry(category: category, message: message), at: 0)
        if entries.count > 300 {
            entries.removeLast(entries.count - 300)
        }
    }

    func clear() {
        entries.removeAll()
    }

    func setBackend(_ name: InputBackendName, message: String) {
        activeBackendName = name
        backendMessage = message
        record("Backend: \(name.rawValue). \(message)", category: .system)
    }

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
