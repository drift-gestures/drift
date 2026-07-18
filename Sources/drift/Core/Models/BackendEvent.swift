import Foundation

/// Identifies which custom recognizer produced an action event.
enum CustomGestureRecognitionSource: Equatable, Sendable {
    case basic
    case advanced
}

/// Observational events emitted after listeners have already applied their effects.
enum BackendEvent: Sendable {
    /// A saved custom gesture passed its configured recognition threshold.
    case customGestureRecognized(
        id: UUID,
        action: CustomGestureAction,
        source: CustomGestureRecognitionSource
    )
}
