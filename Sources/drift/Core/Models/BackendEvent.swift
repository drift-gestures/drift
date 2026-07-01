/// A semantic input action routed to the Timer HUD.
struct TimerHUDInput: Equatable, Sendable {
    /// The kind of gesture-derived Timer HUD input.
    enum Kind: Equatable, Sendable {
        /// A vertical upward scroll gesture.
        case scrollUp
        /// A vertical downward scroll gesture.
        case scrollDown
        /// A horizontal leftward scroll gesture.
        case scrollLeft
        /// A horizontal rightward scroll gesture.
        case scrollRight
        /// A pinch gesture whose scale increased.
        case pinchOut
        /// A pinch gesture whose scale decreased.
        case pinchIn

        /// A human-readable label used in diagnostics or UI.
        var displayName: String {
            switch self {
            case .scrollUp: "Scroll up"
            case .scrollDown: "Scroll down"
            case .scrollLeft: "Scroll left"
            case .scrollRight: "Scroll right"
            case .pinchOut: "Pinch out"
            case .pinchIn: "Pinch in"
            }
        }
    }

    /// The classified input kind.
    let kind: Kind
    /// The absolute gesture delta used to size the resulting Timer HUD adjustment.
    let magnitude: Double
    /// The source trackpad frame that produced the input.
    let frame: Int
}

/// Semantic events emitted by listeners and consumed by app-level UI code.
enum BackendEvent: Sendable {
    /// Requests that the Timer HUD be shown.
    case timerHUDActivationRequested
    /// Requests that the Timer HUD be hidden.
    case timerHUDCloseRequested
    /// Sends a gesture-derived input to the active Timer HUD.
    case timerHUDInput(TimerHUDInput)
}
