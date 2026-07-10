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

/// Reason a listener-owned Timer HUD session closed.
enum TimerHUDCloseReason: Sendable {
    /// The user clicked outside the Timer HUD window.
    case clickOutside
    /// The user pressed Escape while the Timer HUD was active.
    case escape
}

/// Observational events emitted after listeners have already applied their effects.
enum BackendEvent: Sendable {
    /// The Timer HUD was opened by the listener-owned HUD controller.
    case timerHUDDidOpen(source: HUDSessionSource)
    /// The Timer HUD was closed by the listener-owned HUD controller.
    case timerHUDDidClose(reason: TimerHUDCloseReason)
    /// A gesture-derived input was accepted for the active Timer HUD.
    case timerHUDDidReceiveInput(TimerHUDInput)
    /// The Excalidraw HUD was opened by the listener-owned HUD controller.
    case excalidrawHUDDidOpen(source: HUDSessionSource)
    /// The Excalidraw HUD was closed by the listener-owned HUD controller.
    case excalidrawHUDDidClose(reason: ExcalidrawHUDCloseReason)
    /// A gesture-derived input was accepted for the active Excalidraw HUD.
    case excalidrawHUDDidReceiveInput(ExcalidrawHUDInput)
}
