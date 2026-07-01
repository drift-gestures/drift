import CoreGraphics
import Foundation

struct CancellationReason: Hashable, Sendable {
    let description: String

    static let anotherListenerClaimed = CancellationReason(
        description: "Another listener claimed the interaction"
    )
}

enum GestureStatus: Sendable {
    case waiting
    case possible(TrackpadSnapshot)
    case progressing(TrackpadSnapshot)
    case cancelled(TrackpadSnapshot, reason: CancellationReason)
    case ended(TrackpadSnapshot)

    var label: String {
        switch self {
        case .waiting: "waiting"
        case .possible: "possible"
        case .progressing: "progressing"
        case .cancelled: "cancelled"
        case .ended: "ended"
        }
    }
}

enum ScrollAxis: Hashable, Sendable {
    case horizontal
    case vertical
}

enum ScrollDirection: Hashable, Sendable {
    case positive
    case negative
}

enum SuppressionRequest: Hashable, Sendable {
    case scroll(axis: ScrollAxis, direction: ScrollDirection? = nil)
    case press
}

enum SuppressOtherAppEvents: Sendable {
    case scrollEvents
    case pressEvents
}

enum KeyboardModifier: Hashable, Sendable {
    case command
    case control
    case option
    case shift
    case capsLock
    case function
}

struct KeyboardPressInteraction: Sendable {
    let keyCode: UInt16
    let characters: String?
    let modifiers: Set<KeyboardModifier>
}

struct ClickOutsideInteraction: Sendable {
    let hudID: HUDID
    let screenLocation: CGPoint
}

enum Interaction: Sendable {
    case trackpadSnapshot(TrackpadSnapshot)
    case keyboardPress(KeyboardPressInteraction)
    case clickOutside(ClickOutsideInteraction)

    var trackpadSnapshot: TrackpadSnapshot? {
        guard case .trackpadSnapshot(let snapshot) = self else { return nil }
        return snapshot
    }

    var endsCurrentClaim: Bool {
        switch self {
        case .trackpadSnapshot(let snapshot):
            snapshot.phase == .ended
        case .clickOutside:
            true
        case .keyboardPress:
            false
        }
    }
}

struct ListenerDecision: Sendable {
    let stopPropagation: Bool
    let claimInteraction: Bool
    let suppressions: Set<SuppressionRequest>
    let emittedEvents: [BackendEvent]

    init(
        stopPropagation: Bool = false,
        claimInteraction: Bool = false,
        suppressions: Set<SuppressionRequest> = [],
        emittedEvents: [BackendEvent] = []
    ) {
        self.stopPropagation = stopPropagation
        self.claimInteraction = claimInteraction
        self.suppressions = suppressions
        self.emittedEvents = emittedEvents
    }
}

protocol Listener {
    // `set` is the only runtime addition to the board's pseudocode: the Swift bridge needs it to
    // mark other possible listeners as cancelled when one listener claims the interaction.
    var gestureStatus: GestureStatus { get set }

    mutating func onInteraction(_ interaction: Interaction) -> ListenerDecision
}

extension Listener {
    mutating func onInteraction(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        onInteraction(.trackpadSnapshot(snapshot))
    }
}
