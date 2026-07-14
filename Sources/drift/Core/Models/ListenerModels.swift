import CoreGraphics
import Foundation

/// A human-readable reason explaining why a gesture listener cancelled its current recognition.
struct CancellationReason: Hashable, Sendable {
    /// The diagnostic text shown in listener activity logs.
    let description: String

    /// Cancellation reason used when another listener has claimed the same interaction.
    static let anotherListenerClaimed = CancellationReason(
        description: "Another listener claimed the interaction"
    )
}

/// The recognition state for a gesture listener.
enum GestureStatus: Sendable {
    /// The listener is idle and waiting for an interaction that could start a gesture.
    case waiting
    /// The listener has seen a possible gesture start but has not claimed it yet.
    case possible(TrackpadSnapshot)
    /// The listener has recognized and is actively handling a gesture.
    case progressing(TrackpadSnapshot)
    /// The listener rejected the gesture and is waiting for a reset condition.
    case cancelled(TrackpadSnapshot, reason: CancellationReason)
    /// The listener finished recognizing a gesture.
    case ended(TrackpadSnapshot)

    /// A compact diagnostic label for live logging.
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

/// The scroll axis affected by an event suppression request.
enum ScrollAxis: Hashable, Sendable {
    /// Horizontal scroll-wheel movement.
    case horizontal
    /// Vertical scroll-wheel movement.
    case vertical
}

/// A signed scroll direction used to suppress only one side of an axis.
enum ScrollDirection: Hashable, Sendable {
    /// Positive delta values for the requested axis.
    case positive
    /// Negative delta values for the requested axis.
    case negative
}

/// A request from a listener to block or edit foreground-app input events.
enum SuppressionRequest: Hashable, Sendable {
    /// Suppresses scroll events for an axis, optionally limited to one direction.
    case scroll(axis: ScrollAxis, direction: ScrollDirection? = nil)
    /// Suppresses mouse button press/release pairs.
    case press
    /// Suppresses key-down and matching key-up events for a specific hardware key code.
    case keyPress(keyCode: UInt16)
}

extension Set where Element == SuppressionRequest {
    /// Checks whether this suppression set contains a key-press request for a key code.
    /// - Parameter keyCode: The hardware key code to test.
    /// - Returns: `true` when the set contains a matching key-press suppression.
    func containsKeyPress(_ keyCode: UInt16) -> Bool {
        contains { request in
            guard case .keyPress(let requestedKeyCode) = request else { return false }
            return requestedKeyCode == keyCode
        }
    }
}

/// Legacy coarse event-suppression categories.
enum SuppressOtherAppEvents: Sendable {
    /// Suppress scroll-wheel events.
    case scrollEvents
    /// Suppress press events.
    case pressEvents
}

/// Keyboard modifiers normalized across AppKit and CoreGraphics event sources.
enum KeyboardModifier: String, Codable, Hashable, Sendable {
    /// The Command modifier.
    case command
    /// The Control modifier.
    case control
    /// The Option modifier.
    case option
    /// The Shift modifier.
    case shift
    /// The Caps Lock modifier.
    case capsLock
    /// The Function modifier.
    case function
}

/// A normalized key press delivered to gesture listeners.
struct KeyboardPressInteraction: Sendable {
    /// The hardware key code for the pressed key.
    let keyCode: UInt16
    /// Printable characters for the key press, when available from the event source.
    let characters: String?
    /// Modifier keys active when the key press occurred.
    let modifiers: Set<KeyboardModifier>
}

/// The complete set of modifier keys currently held by the user.
struct ModifierStateInteraction: Sendable {
    let modifiers: Set<KeyboardModifier>
}

/// Hardware key codes used by listener logic.
enum KeyboardKey {
    /// The macOS hardware key code for Escape.
    static let escape: UInt16 = 53
    /// The macOS hardware key code for Return.
    static let `return`: UInt16 = 36
    /// The macOS hardware key code for keypad Enter.
    static let keypadEnter: UInt16 = 76
    /// The macOS hardware key code for W.
    static let w: UInt16 = 13
    /// The macOS hardware key code for S.
    static let s: UInt16 = 1
    /// The macOS hardware key code for Up Arrow.
    static let upArrow: UInt16 = 126
    /// The macOS hardware key code for Down Arrow.
    static let downArrow: UInt16 = 125

    /// Checks whether a key code should activate a default Return-style HUD action.
    /// - Parameter keyCode: The hardware key code to test.
    /// - Returns: `true` for Return and keypad Enter.
    static func isReturn(_ keyCode: UInt16) -> Bool {
        keyCode == Self.return || keyCode == Self.keypadEnter
    }
}

/// A mouse click that occurred outside a displayed HUD window.
struct ClickOutsideInteraction: Sendable {
    /// The HUD whose window did not contain the click.
    let hudID: HUDID
    /// The click location in screen coordinates.
    let screenLocation: CGPoint
}

/// One normalized input interaction that can be evaluated by listeners.
enum Interaction: Sendable {
    /// A trackpad frame from the multitouch bridge.
    case trackpadSnapshot(TrackpadSnapshot)
    /// A classified chassis tap/slap from the accelerometer bridge.
    case impactEvent(ImpactSnapshot)
    /// A keyboard press from AppKit or the event tap.
    case keyboardPress(KeyboardPressInteraction)
    /// A modifier press or release, including otherwise keyless `flagsChanged` events.
    case modifierStateChanged(ModifierStateInteraction)
    /// A mouse click outside a HUD window.
    case clickOutside(ClickOutsideInteraction)

    /// The associated trackpad snapshot when the interaction is a trackpad frame.
    var trackpadSnapshot: TrackpadSnapshot? {
        guard case .trackpadSnapshot(let snapshot) = self else { return nil }
        return snapshot
    }

    /// Whether this interaction should release the currently claimed listener interaction.
    var endsCurrentClaim: Bool {
        switch self {
        case .trackpadSnapshot(let snapshot):
            snapshot.phase == .ended
        case .impactEvent:
            false
        case .clickOutside:
            true
        case .keyboardPress(let keyPress):
            keyPress.keyCode == KeyboardKey.escape
        case .modifierStateChanged:
            false
        }
    }
}

/// The result of allowing one listener to evaluate an interaction.
struct ListenerDecision: Sendable {
    /// Whether later listeners should be skipped for the current interaction.
    let stopPropagation: Bool
    /// Whether this listener should become the exclusive handler until the interaction ends.
    let claimInteraction: Bool
    /// Foreground-app input events that should be suppressed while this decision is active.
    let suppressions: Set<SuppressionRequest>
    /// Observational events emitted after this listener has already applied its effects.
    let emittedEvents: [BackendEvent]

    /// Creates a listener decision.
    /// - Parameters:
    ///   - stopPropagation: Whether to stop calling later listeners for this interaction.
    ///   - claimInteraction: Whether this listener should exclusively receive the current interaction.
    ///   - suppressions: Input suppression requests to apply to foreground-app events.
    ///   - emittedEvents: Completed listener effects to deliver for logging or UI synchronization.
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

/// A stateful recognizer that converts normalized interactions into listener decisions.
protocol Listener {
    /// The listener's current recognition state.
    ///
    /// This property is mutable so the pipeline can cancel competing listeners when another
    /// listener claims the current interaction.
    var gestureStatus: GestureStatus { get set }

    /// Whether this listener receives trackpad input while the advanced activation key is held.
    var listensDuringAdvancedGestureMode: Bool { get }

    /// Handles one normalized interaction and returns the listener's routing decision.
    /// - Parameter interaction: The interaction to evaluate.
    /// - Returns: The decision produced by this listener.
    mutating func onInteraction(_ interaction: Interaction) -> ListenerDecision
}

extension Listener {
    var listensDuringAdvancedGestureMode: Bool { false }
    /// Convenience overload for listeners that are driven directly by trackpad snapshots.
    /// - Parameter snapshot: The trackpad snapshot to evaluate.
    /// - Returns: The decision produced by this listener.
    mutating func onInteraction(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        onInteraction(.trackpadSnapshot(snapshot))
    }
}
