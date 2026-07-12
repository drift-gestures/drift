import AppKit
import CoreGraphics
import Foundation

/// Recognizes Timer HUD activation and follow-up timer adjustment gestures.
struct TimerHUDInputListener: Listener {
    /// Current recognition state used by the listener pipeline.
    var gestureStatus: GestureStatus = .waiting

    /// Runtime handle used to own Timer HUD lifecycle and message delivery.
    private let hudController: HUDController?
    private let isTimerEnabled: () -> Bool
    private let isPomodoroEnabled: () -> Bool
    /// Last contact center used as the baseline for activation or input deltas.
    private var pendingCenter: CGPoint?
    /// Last scale value used to classify pinch input.
    private var pendingScale = 1.0
    /// How the current Timer HUD input stream was started.
    private var activationSource: TimerHUDActivationSource?
    /// Initial mode requested by the current activation gesture.
    private var pendingActivationMode: TimerHUDMode?

    /// Minimum normalized movement needed to activate the Timer HUD.
    private let activationThreshold: CGFloat = 0.1
    /// Maximum normalized X coordinate for activation start.
    private let activationStartMaxX: CGFloat = 0.1
    /// Maximum normalized Y coordinate for activation start.
    private let activationStartMaxY: CGFloat = 0.07
    /// Maximum normalized X coordinate for direct Pomodoro activation.
    private let pomodoroActivationStartMaxX: CGFloat = 0.25
    /// Minimum center movement needed to emit a scroll-style Timer HUD input.
    private let scrollThreshold = 0.01
    /// Minimum scale delta needed to emit a pinch-style Timer HUD input.
    private let pinchThreshold = 0.04

    /// Creates a Timer HUD listener.
    /// - Parameters:
    ///   - hudController: Optional lifecycle handle for HUD ownership.
    init(
        hudController: HUDController? = nil,
        isTimerEnabled: @escaping () -> Bool = { true },
        isPomodoroEnabled: @escaping () -> Bool = { true }
    ) {
        self.hudController = hudController
        self.isTimerEnabled = isTimerEnabled
        self.isPomodoroEnabled = isPomodoroEnabled
    }

    /// Routes one interaction to the Timer HUD state machine.
    /// - Parameter interaction: The normalized input interaction to process.
    /// - Returns: The listener decision for the interaction.
    mutating func onInteraction(_ interaction: Interaction) -> ListenerDecision {
        switch interaction {
        case .clickOutside(let click):
            return onClickOutside(click)
        case .keyboardPress(let keyPress):
            return onKeyboardPress(keyPress)
        case .trackpadSnapshot(let snapshot):
            return onTrackpadSnapshot(snapshot)
        case .modifierStateChanged:
            return ListenerDecision()
        }
    }

    /// Handles trackpad frames according to the listener's current gesture state.
    /// - Parameter snapshot: The trackpad frame to evaluate.
    /// - Returns: The resulting listener decision.
    private mutating func onTrackpadSnapshot(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard isTimerEnabled() || isPomodoroEnabled() else {
            reset()
            return ListenerDecision()
        }
        switch gestureStatus {
        case .waiting:
            if isTimerHUDActiveForTesting {
                return startTimerInput(for: snapshot)
            }
            return checkForTimerActivationStart(snapshot)
        case .possible:
            if snapshot.phase == .ended {
                gestureStatus = .cancelled(snapshot, reason: CancellationReason(description: "User released during `.possible` state"))
                reset()
                return ListenerDecision()
            } else {
                return checkForTimerActivationProgress(snapshot)
            }
        case .progressing:
            return receiveTimerInput(snapshot)
        case .cancelled, .ended:
            if snapshot.phase == .ended {
                reset()
            }
            return ListenerDecision()
        }
    }

    /// Starts HUD input handling when the Timer HUD is already visible.
    /// - Parameter snapshot: The first frame to use as the input baseline.
    /// - Returns: A claimed decision that suppresses foreground scroll while collecting deltas.
    private mutating func startTimerInput(for snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard snapshot.fingerCount == 2, snapshot.phase != .ended else {
            return ListenerDecision()
        }

        pendingCenter = snapshot.center
        pendingScale = snapshot.scale
        activationSource = .testingHUD
        gestureStatus = .progressing(snapshot)
        return ListenerDecision(
            claimInteraction: true,
            suppressions: activeSuppressions
        )
    }

    /// Handles keyboard behavior for Timer HUD shortcuts.
    /// - Parameter keyPress: The normalized keyboard press.
    /// - Returns: The listener decision, including key suppression when handled.
    private mutating func onKeyboardPress(_ keyPress: KeyboardPressInteraction) -> ListenerDecision {
        if keyPress.keyCode == KeyboardKey.escape {
            return onEscapePress()
        }
        if KeyboardKey.isReturn(keyPress.keyCode)  {
            return onReturnPress(keyPress)
        }
        return ListenerDecision()
    }

    /// Handles Escape-key behavior for closing or cancelling Timer HUD gestures.
    /// - Returns: The listener decision, including Escape suppression when handled.
    private mutating func onEscapePress() -> ListenerDecision {
        let suppressions: Set<SuppressionRequest> = [.keyPress(keyCode: KeyboardKey.escape)]

        switch gestureStatus {
        case .waiting:
            guard isTimerHUDActive else { return ListenerDecision() }
            guard closeTimerHUD() else { return ListenerDecision() }
            return ListenerDecision(
                suppressions: suppressions,
                emittedEvents: [.timerHUDDidClose(reason: .escape)]
            )
        case .possible(let snapshot):
            gestureStatus = .cancelled(
                snapshot,
                reason: CancellationReason(description: "User pressed Escape during `.possible` state")
            )
            reset()
            return ListenerDecision(suppressions: suppressions)
        case .progressing:
            guard closeTimerHUD() else { return ListenerDecision() }
            return ListenerDecision(
                suppressions: suppressions,
                emittedEvents: [.timerHUDDidClose(reason: .escape)]
            )
        case .cancelled, .ended:
            guard isTimerHUDActive else { return ListenerDecision() }
            guard closeTimerHUD() else { return ListenerDecision() }
            return ListenerDecision(
                suppressions: suppressions,
                emittedEvents: [.timerHUDDidClose(reason: .escape)]
            )
        }
    }

    /// Handles Return-key behavior for visible Timer HUD default actions.
    /// - Parameter keyPress: The normalized keyboard press.
    /// - Returns: The listener decision, including Return suppression when handled.
    private mutating func onReturnPress(_ keyPress: KeyboardPressInteraction) -> ListenerDecision {
        guard keyPress.modifiers.isEmpty,
              isTimerHUDActive,
              sendTimerHUDDefaultAction()
        else {
            return ListenerDecision()
        }

        return ListenerDecision(
            suppressions: [.keyPress(keyCode: keyPress.keyCode)]
        )
    }

    /// Handles mouse clicks outside the Timer HUD window.
    /// - Parameter click: The outside-click interaction to evaluate.
    /// - Returns: A close request when the click belongs to the Timer HUD.
    private mutating func onClickOutside(_ click: ClickOutsideInteraction) -> ListenerDecision {
        guard click.hudID == TimerHUDDefinition.hudID else { return ListenerDecision() }

        guard closeTimerHUD() else { return ListenerDecision() }
        return ListenerDecision(emittedEvents: [.timerHUDDidClose(reason: .clickOutside)])
    }

    /// Checks whether a snapshot can start the bottom-left two-finger activation gesture.
    /// - Parameter snapshot: The candidate trackpad snapshot.
    /// - Returns: A neutral decision after recording `.possible`, or no-op if the snapshot is not eligible.
    private mutating func checkForTimerActivationStart(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard snapshot.fingerCount == 2,
              let activationMode = activationMode(for: snapshot.center),
              isEnabled(activationMode)
        else {
            return ListenerDecision()
        }
        pendingCenter = snapshot.center
        pendingScale = snapshot.scale
        pendingActivationMode = activationMode
        gestureStatus = .possible(snapshot)
        return ListenerDecision()
    }

    private func isEnabled(_ mode: TimerHUDMode) -> Bool {
        switch mode {
        case .timer: isTimerEnabled()
        case .pomodoro: isPomodoroEnabled()
        }
    }

    /// Advances a possible activation gesture until it activates or cancels.
    /// - Parameter snapshot: The next snapshot in the possible activation gesture.
    /// - Returns: A claim and activation request when the upward movement threshold is met.
    private mutating func checkForTimerActivationProgress(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard snapshot.fingerCount == 2 else {
            return cancelGesture(with: snapshot)
        }
        guard let pendingCenter else {
            return cancelGesture(with: snapshot)
        }

        let deltaX = snapshot.center.x - pendingCenter.x
        let deltaY = snapshot.center.y - pendingCenter.y
        let dominantMovement = max(abs(deltaX), abs(deltaY))
        guard dominantMovement >= activationThreshold else {
            gestureStatus = .possible(snapshot)
            return ListenerDecision(suppressions: activeSuppressions)
        }
        guard deltaY >= activationThreshold, deltaY >= abs(deltaX) else {
            return cancelGesture(with: snapshot)
        }

        self.pendingCenter = snapshot.center
        pendingScale = snapshot.scale
        activationSource = .activationGesture
        gestureStatus = .progressing(snapshot)
        guard openTimerHUD(source: .listener, initialMode: pendingActivationMode ?? .timer) else {
            reset()
            return ListenerDecision()
        }
        return ListenerDecision(
            claimInteraction: true,
            suppressions: activeSuppressions,
            emittedEvents: [.timerHUDDidOpen(source: .listener)]
        )
    }

    /// Converts progressing two-finger gestures into Timer HUD input events.
    /// - Parameter snapshot: The current progressing gesture snapshot.
    /// - Returns: A claimed decision with optional input and foreground-event suppressions.
    private mutating func receiveTimerInput(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard hudController == nil || isTimerHUDActive else {
            reset()
            return ListenerDecision()
        }

        if activationSource == .testingHUD && !isTimerHUDActiveForTesting {
            reset()
            return ListenerDecision()
        }

        guard snapshot.fingerCount == 2 else {
            return ListenerDecision()
        }

        if snapshot.phase == .began || pendingCenter == nil {
            pendingCenter = snapshot.center
            pendingScale = snapshot.scale
            return ListenerDecision()
        }

        guard let input = classifyInput(
            from: pendingCenter!,
            pendingScale: pendingScale,
            to: snapshot
        ) else {
            gestureStatus = .progressing(snapshot)
            return ListenerDecision(
                claimInteraction: true,
                suppressions: activeSuppressions
            )
        }

        self.pendingCenter = snapshot.center
        pendingScale = snapshot.scale
        gestureStatus = .progressing(snapshot)
        guard sendTimerHUDInput(input) else {
            clearTracking()
            return ListenerDecision()
        }
        return ListenerDecision(
            claimInteraction: true,
            suppressions: suppressions(for: input),
            emittedEvents: [.timerHUDDidReceiveInput(input)]
        )
    }

    /// Suppressions active while a Timer HUD gesture is possible or progressing.
    private var activeSuppressions: Set<SuppressionRequest> {
        withEscapeSuppression([.scroll(axis: .vertical), .scroll(axis: .horizontal)])
    }

    /// Chooses foreground-event suppressions for a classified Timer HUD input.
    /// - Parameter input: The input emitted from gesture classification.
    /// - Returns: Suppressions for the foreground events that should stay blocked.
    private func suppressions(for input: TimerHUDInput) -> Set<SuppressionRequest> {
        switch input.kind {
        case .scrollUp, .scrollDown, .scrollLeft, .scrollRight:
            // Trackpad swipes often include off-axis deltas, so keep both axes suppressed.
            return activeSuppressions
        case .pinchOut, .pinchIn:
            return withEscapeSuppression([])
        }
    }

    /// Adds Escape-key suppression to a suppression set.
    /// - Parameter suppressions: Suppressions to combine with Escape handling.
    /// - Returns: The combined suppression set.
    private func withEscapeSuppression(_ suppressions: Set<SuppressionRequest>) -> Set<SuppressionRequest> {
        suppressions.union([.keyPress(keyCode: KeyboardKey.escape)])
    }

    /// Sends a default-action request to the visible Timer HUD view.
    /// - Returns: `true` when the active HUD accepted the message.
    private func sendTimerHUDDefaultAction() -> Bool {
        hudController?.send(.timer(.defaultAction), to: TimerHUDDefinition.hudID) ?? false
    }

    /// Whether the Timer HUD is currently visible according to the shared visibility mirror.
    private var isTimerHUDActive: Bool {
        hudController?.isActive(TimerHUDDefinition.hudID) ?? false
    }

    /// Whether the Timer HUD was opened through a testing-only control.
    private var isTimerHUDActiveForTesting: Bool {
        hudController?.isTesting(TimerHUDDefinition.hudID) ?? false
    }

    /// Opens the Timer HUD through the listener-owned HUD controller.
    /// - Parameter source: Source for the new HUD session.
    /// - Returns: `true` when the Timer HUD is active.
    private func openTimerHUD(source: HUDSessionSource, initialMode: TimerHUDMode = .timer) -> Bool {
        hudController?.open(
            TimerHUDDefinition.hudID,
            source: source,
            state: HUDState(TimerHUDState(initialMode: initialMode))
        ) ?? true
    }

    /// Closes the Timer HUD through the listener-owned HUD controller and resets after success.
    /// - Returns: `true` when the Timer HUD was closed or no controller is installed.
    private mutating func closeTimerHUD() -> Bool {
        guard let hudController else {
            reset()
            return true
        }
        guard hudController.close(TimerHUDDefinition.hudID) else { return false }
        reset()
        return true
    }

    /// Delivers input through the listener-owned HUD controller.
    /// - Parameter input: Timer HUD input payload.
    /// - Returns: `true` when the message was accepted.
    private func sendTimerHUDInput(_ input: TimerHUDInput) -> Bool {
        hudController?.send(.timer(.input(input)), to: TimerHUDDefinition.hudID) ?? true
    }

    /// Returns the requested initial mode for a bottom-edge activation start.
    /// - Parameter center: The normalized contact center.
    /// - Returns: The mode to open, or `nil` when the start point is outside activation lanes.
    private func activationMode(for center: CGPoint) -> TimerHUDMode? {
        guard center.y <= activationStartMaxY else { return nil }
        if center.x <= activationStartMaxX {
            return .timer
        }
        if center.x <= pomodoroActivationStartMaxX {
            return .pomodoro
        }
        return nil
    }

    /// Cancels the current activation gesture and clears tracked baseline values.
    /// - Parameter snapshot: The snapshot that caused cancellation.
    /// - Returns: A neutral listener decision.
    private mutating func cancelGesture(with snapshot: TrackpadSnapshot) -> ListenerDecision {
        clearTracking()
        gestureStatus = .cancelled(snapshot, reason: .timerHUDGestureRuleBroken)
        return ListenerDecision()
    }

    /// Clears all tracked gesture values and returns to the waiting state.
    private mutating func reset() {
        clearTracking()
        gestureStatus = .waiting
    }

    /// Clears only the tracked baseline values used for gesture deltas.
    private mutating func clearTracking() {
        pendingCenter = nil
        pendingScale = 1.0
        activationSource = nil
        pendingActivationMode = nil
    }

    /// Classifies movement since the previous baseline into a Timer HUD input.
    /// - Parameters:
    ///   - center: Previous normalized contact center.
    ///   - pendingScale: Previous aggregate scale value.
    ///   - snapshot: Current trackpad snapshot to classify.
    /// - Returns: A Timer HUD input when movement exceeds a threshold.
    private func classifyInput(
        from center: CGPoint,
        pendingScale: Double,
        to snapshot: TrackpadSnapshot
    ) -> TimerHUDInput? {
        let deltaX = snapshot.center.x - center.x
        let deltaY = snapshot.center.y - center.y
        let scaleDelta = snapshot.scale - pendingScale

        if abs(scaleDelta) >= pinchThreshold {
            return TimerHUDInput(
                kind: scaleDelta > 0 ? .pinchOut : .pinchIn,
                magnitude: abs(scaleDelta),
                frame: snapshot.frame
            )
        }

        let horizontalMagnitude = abs(deltaX)
        let verticalMagnitude = abs(deltaY)
        guard max(horizontalMagnitude, verticalMagnitude) >= scrollThreshold else { return nil }

        let kind: TimerHUDInput.Kind
        let magnitude: Double
        if verticalMagnitude >= horizontalMagnitude {
            kind = deltaY >= 0 ? .scrollUp : .scrollDown
            magnitude = verticalMagnitude
        } else {
            kind = deltaX >= 0 ? .scrollRight : .scrollLeft
            magnitude = horizontalMagnitude
        }

        return TimerHUDInput(kind: kind, magnitude: magnitude, frame: snapshot.frame)
    }
}

private extension CancellationReason {
    /// Cancellation reason used when Timer HUD activation movement violates the gesture rule.
    static let timerHUDGestureRuleBroken = CancellationReason(
        description: "Timer HUD gesture rule broken"
    )
}

/// The source that started a Timer HUD input stream.
private enum TimerHUDActivationSource: String {
    /// The user performed the real Timer HUD activation gesture.
    case activationGesture
    /// The Timer HUD was opened through temporary testing controls.
    case testingHUD
}
