struct TimerHUDInput: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case scrollUp
        case scrollDown
        case scrollLeft
        case scrollRight
        case pinchOut
        case pinchIn

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

    let kind: Kind
    let magnitude: Double
    let frame: Int
}

enum BackendEvent: Sendable {
    case timerHUDActivationRequested
    case timerHUDCloseRequested
    case timerHUDInput(TimerHUDInput)
}
