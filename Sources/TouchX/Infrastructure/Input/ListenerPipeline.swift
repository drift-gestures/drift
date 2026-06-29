import Foundation

struct ListenerActivity: Sendable {
    let listenerName: String
    let status: GestureStatus
}

struct ListenerPipelineResult: Sendable {
    let events: [BackendEvent]
    let suppressions: Set<SuppressionRequest>
    let activities: [ListenerActivity]
    let didClaimInteraction: Bool
}

/// Calls listener structs synchronously in registration order.
final class ListenerPipeline {
    private var listeners: [any Listener]
    private var claimedListenerIndex: Int?
    private var cancelledListenerIndices: Set<Int> = []

    init(listeners: [any Listener]) {
        self.listeners = listeners
    }

    func process(_ snapshot: TrackpadSnapshot) -> ListenerPipelineResult {
        if let claimedListenerIndex {
            return processClaimedInteraction(snapshot, claimedIndex: claimedListenerIndex)
        }

        var events: [BackendEvent] = []
        var suppressions: Set<SuppressionRequest> = []
        var activities: [ListenerActivity] = []
        var didClaim = false

        for index in listeners.indices {
            let decision = listeners[index].onStateChange(snapshot)
            events.append(contentsOf: decision.emittedEvents)
            suppressions.formUnion(decision.suppressions)
            activities.append(activity(for: index))

            if decision.claimInteraction {
                didClaim = true
                claimedListenerIndex = index
                // Once this listener claims the interaction, only its decision remains effective.
                events = decision.emittedEvents
                suppressions = decision.suppressions
                cancelOtherPossibleListeners(except: index, with: snapshot, activities: &activities)
                break
            }
            if decision.stopPropagation {
                break
            }
        }

        if snapshot.phase == .ended {
            clearClaim()
            didClaim = false
        }

        return ListenerPipelineResult(
            events: events,
            suppressions: suppressions,
            activities: activities,
            didClaimInteraction: didClaim
        )
    }

    private func processClaimedInteraction(
        _ snapshot: TrackpadSnapshot,
        claimedIndex: Int
    ) -> ListenerPipelineResult {
        let decision = listeners[claimedIndex].onStateChange(snapshot)
        var activities = [activity(for: claimedIndex)]

        // Cancelled listeners still receive snapshots so their own state machines can decide when
        // they are allowed to return to `.waiting`. Their decisions are intentionally ignored.
        for index in cancelledListenerIndices.sorted() {
            _ = listeners[index].onStateChange(snapshot)
            activities.append(activity(for: index))
        }

        if snapshot.phase == .ended {
            clearClaim()
        }

        return ListenerPipelineResult(
            events: decision.emittedEvents,
            suppressions: decision.suppressions,
            activities: activities,
            didClaimInteraction: snapshot.phase != .ended
        )
    }

    private func cancelOtherPossibleListeners(
        except claimedIndex: Int,
        with snapshot: TrackpadSnapshot,
        activities: inout [ListenerActivity]
    ) {
        for index in listeners.indices where index != claimedIndex {
            switch listeners[index].gestureStatus {
            case .possible, .progressing:
                listeners[index].gestureStatus = .cancelled(
                    snapshot,
                    reason: .anotherListenerClaimed
                )
                cancelledListenerIndices.insert(index)
                activities.append(activity(for: index))
            case .cancelled:
                // It was already cancelled by its own rules, but must keep receiving reset frames.
                cancelledListenerIndices.insert(index)
            case .waiting, .ended:
                break
            }
        }
    }

    private func activity(for index: Int) -> ListenerActivity {
        ListenerActivity(
            listenerName: String(describing: type(of: listeners[index])),
            status: listeners[index].gestureStatus
        )
    }

    private func clearClaim() {
        claimedListenerIndex = nil
        cancelledListenerIndices.removeAll()
    }
}
