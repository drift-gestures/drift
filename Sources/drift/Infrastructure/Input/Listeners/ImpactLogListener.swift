import Foundation

/// Observes chassis impact events and surfaces them as backend events for the live log.
///
/// This is intentionally the simplest possible listener: it never claims the interaction and never
/// requests suppression, since v1 of chassis tap/slap detection is observation-only. It exists so
/// impacts flow through the same `BackendEvent` reporting path as every other semantic listener.
struct ImpactLogListener: Listener {
    var gestureStatus: GestureStatus = .waiting

    mutating func onInteraction(_ interaction: Interaction) -> ListenerDecision {
        guard case .impactEvent(let impact) = interaction else { return ListenerDecision() }
        return ListenerDecision(emittedEvents: [.impactDetected(impact)])
    }
}
