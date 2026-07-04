import Foundation

/// A diagnostic snapshot of one listener after processing an interaction.
struct ListenerActivity: Sendable {
    /// The concrete listener type name shown in the live log.
    let listenerName: String
    /// The listener state after it processed the interaction.
    let status: GestureStatus
}

/// The aggregate result produced after an interaction passes through the listener pipeline.
struct ListenerPipelineResult: Sendable {
    /// Semantic events emitted by the effective listener decisions.
    let events: [BackendEvent]
    /// Foreground-app event suppressions requested by the effective listener decisions.
    let suppressions: Set<SuppressionRequest>
    /// Listener state transitions recorded for diagnostics.
    let activities: [ListenerActivity]
    /// Whether a listener currently owns the interaction exclusively.
    let didClaimInteraction: Bool

    /// Creates an aggregate listener result.
    /// - Parameters:
    ///   - events: Semantic events emitted by effective listener decisions.
    ///   - suppressions: Foreground-app event suppressions requested by listeners.
    ///   - activities: Listener state transitions recorded for diagnostics.
    ///   - didClaimInteraction: Whether a listener owns the interaction exclusively.
    init(
        events: [BackendEvent] = [],
        suppressions: Set<SuppressionRequest> = [],
        activities: [ListenerActivity] = [],
        didClaimInteraction: Bool = false
    ) {
        self.events = events
        self.suppressions = suppressions
        self.activities = activities
        self.didClaimInteraction = didClaimInteraction
    }

    /// Whether a local key-down should be consumed before it reaches AppKit responders.
    /// - Parameter keyCode: Hardware key code to check.
    /// - Returns: `true` when a listener claimed the key interaction or requested its suppression.
    func consumesKeyPress(_ keyCode: UInt16) -> Bool {
        didClaimInteraction || suppressions.containsKeyPress(keyCode)
    }
}

/// Calls listener structs synchronously in registration order and manages exclusive claims.
final class ListenerPipeline {
    /// Registered listeners in evaluation order.
    private var listeners: [any Listener]
    /// The listener that currently owns the interaction, if any.
    private var claimedListenerIndex: Int?
    /// Listeners cancelled by the current owner that still need reset frames.
    private var cancelledListenerIndices: Set<Int> = []

    /// Creates a pipeline from an ordered listener list.
    /// - Parameter listeners: Listeners to evaluate in registration order.
    init(listeners: [any Listener]) {
        self.listeners = listeners
    }

    /// Processes a trackpad snapshot through the pipeline.
    /// - Parameter snapshot: The snapshot to wrap as a trackpad interaction.
    /// - Returns: The aggregate pipeline result.
    func process(_ snapshot: TrackpadSnapshot) -> ListenerPipelineResult {
        process(.trackpadSnapshot(snapshot))
    }

    /// Processes one normalized interaction through the pipeline.
    /// - Parameter interaction: The input interaction to evaluate.
    /// - Returns: The effective events, suppressions, and listener activity.
    func process(_ interaction: Interaction) -> ListenerPipelineResult {
        if let claimedListenerIndex {
            return processClaimedInteraction(interaction, claimedIndex: claimedListenerIndex)
        }

        var events: [BackendEvent] = []
        var suppressions: Set<SuppressionRequest> = []
        var activities: [ListenerActivity] = []
        var didClaim = false

        for index in listeners.indices {
            let decision = listeners[index].onInteraction(interaction)
            events.append(contentsOf: decision.emittedEvents)
            suppressions.formUnion(decision.suppressions)
            activities.append(activity(for: index))

            if decision.claimInteraction {
                didClaim = true
                claimedListenerIndex = index
                // Once this listener claims the interaction, only its decision remains effective.
                events = decision.emittedEvents
                suppressions = decision.suppressions
                cancelOtherPossibleListeners(
                    except: index,
                    with: interaction.trackpadSnapshot,
                    activities: &activities
                )
                break
            }
            if decision.stopPropagation {
                break
            }
        }

        if interaction.endsCurrentClaim {
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

    /// Sends an interaction only to the listener that currently owns it.
    /// - Parameters:
    ///   - interaction: The interaction to process.
    ///   - claimedIndex: The index of the listener that owns the interaction.
    /// - Returns: The result produced by the claimed listener, plus reset activity.
    private func processClaimedInteraction(
        _ interaction: Interaction,
        claimedIndex: Int
    ) -> ListenerPipelineResult {
        let decision = listeners[claimedIndex].onInteraction(interaction)
        var activities = [activity(for: claimedIndex)]

        // Cancelled listeners still receive snapshots so their own state machines can decide when
        // they are allowed to return to `.waiting`. Their decisions are intentionally ignored.
        for index in cancelledListenerIndices.sorted() {
            _ = listeners[index].onInteraction(interaction)
            activities.append(activity(for: index))
        }

        if interaction.endsCurrentClaim {
            clearClaim()
        }

        return ListenerPipelineResult(
            events: decision.emittedEvents,
            suppressions: decision.suppressions,
            activities: activities,
            didClaimInteraction: !interaction.endsCurrentClaim
        )
    }

    /// Cancels non-owning listeners that were already considering the same interaction.
    /// - Parameters:
    ///   - claimedIndex: The listener that owns the interaction.
    ///   - snapshot: The trackpad snapshot used as cancellation context.
    ///   - activities: Activity log entries to append cancellation transitions to.
    private func cancelOtherPossibleListeners(
        except claimedIndex: Int,
        with snapshot: TrackpadSnapshot?,
        activities: inout [ListenerActivity]
    ) {
        guard let snapshot else { return }

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

    /// Builds a diagnostic activity value for one listener.
    /// - Parameter index: The listener index to describe.
    /// - Returns: The listener name and current status.
    private func activity(for index: Int) -> ListenerActivity {
        ListenerActivity(
            listenerName: String(describing: type(of: listeners[index])),
            status: listeners[index].gestureStatus
        )
    }

    /// Clears the current interaction owner and any cancelled-listener reset bookkeeping.
    private func clearClaim() {
        claimedListenerIndex = nil
        cancelledListenerIndices.removeAll()
    }
}
