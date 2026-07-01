import AppKit
import CoreGraphics
import Foundation

/// Recognizes Timer HUD activation and follow-up timer adjustment gestures.
struct TimerHUDInputListener: Listener {
    /// Current recognition state used by the listener pipeline.
    var gestureStatus: GestureStatus = .waiting

    /// Cross-thread visibility mirror used to let Escape close an already visible Timer HUD.
    private let hudVisibilityState: HUDVisibilityState?
    /// Last contact center used as the baseline for activation or input deltas.
    private var pendingCenter: CGPoint?
    /// Last scale value used to classify pinch input.
    private var pendingScale = 1.0
    /// Multiplier that normalizes upward movement for normal and inverted trackpad Y axes.
    private var pendingUpDirectionY: CGFloat = 1

    /// Minimum normalized movement needed to activate the Timer HUD.
    private let activationThreshold: CGFloat = 0.1
    /// Maximum normalized X position that still counts as the left activation edge.
    private let bottomLeftEdgeLimit: CGFloat = 0.1
    /// Distance from either vertical edge that counts as a bottom-left activation corner.
    private let bottomEdgeLimit: CGFloat = 0.15
    /// Minimum center movement needed to emit a scroll-style Timer HUD input.
    private let scrollThreshold = 0.01
    /// Minimum scale delta needed to emit a pinch-style Timer HUD input.
    private let pinchThreshold = 0.04

    /// Creates a Timer HUD listener.
    /// - Parameter hudVisibilityState: Optional visibility mirror used for Escape-key close behavior.
    init(hudVisibilityState: HUDVisibilityState? = nil) {
        self.hudVisibilityState = hudVisibilityState
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
        }
    }

    /// Handles trackpad frames according to the listener's current gesture state.
    /// - Parameter snapshot: The trackpad frame to evaluate.
    /// - Returns: The resulting listener decision.
    private mutating func onTrackpadSnapshot(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        switch gestureStatus {
        case .waiting:
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

    /// Handles Escape-key behavior for closing or cancelling Timer HUD gestures.
    /// - Parameter keyPress: The normalized keyboard press.
    /// - Returns: The listener decision, including Escape suppression when handled.
    private mutating func onKeyboardPress(_ keyPress: KeyboardPressInteraction) -> ListenerDecision {
        guard keyPress.keyCode == KeyboardKey.escape else { return ListenerDecision() }

        let suppressions: Set<SuppressionRequest> = [.keyPress(keyCode: KeyboardKey.escape)]

        switch gestureStatus {
        case .waiting:
            guard isTimerHUDActive else { return ListenerDecision() }
            reset()
            return ListenerDecision(
                suppressions: suppressions,
                emittedEvents: [.timerHUDCloseRequested]
            )
        case .possible(let snapshot):
            gestureStatus = .cancelled(
                snapshot,
                reason: CancellationReason(description: "User pressed Escape during `.possible` state")
            )
            reset()
            return ListenerDecision(suppressions: suppressions)
        case .progressing:
            reset()
            return ListenerDecision(
                suppressions: suppressions,
                emittedEvents: [.timerHUDCloseRequested]
            )
        case .cancelled, .ended:
            guard isTimerHUDActive else { return ListenerDecision() }
            reset()
            return ListenerDecision(
                suppressions: suppressions,
                emittedEvents: [.timerHUDCloseRequested]
            )
        }
    }

    /// Handles mouse clicks outside the Timer HUD window.
    /// - Parameter click: The outside-click interaction to evaluate.
    /// - Returns: A close request when the click belongs to the Timer HUD.
    private mutating func onClickOutside(_ click: ClickOutsideInteraction) -> ListenerDecision {
        guard click.hudID == TimerHUDDefinition.hudID else { return ListenerDecision() }

        reset()
        return ListenerDecision(emittedEvents: [.timerHUDCloseRequested])
    }

    /// Checks whether a snapshot can start the bottom-left two-finger activation gesture.
    /// - Parameter snapshot: The candidate trackpad snapshot.
    /// - Returns: A neutral decision after recording `.possible`, or no-op if the snapshot is not eligible.
    private mutating func checkForTimerActivationStart(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard snapshot.fingerCount == 2,
              let upDirectionY = upDirectionY(for: snapshot.center)
        else {
            return ListenerDecision()
        }
        pendingCenter = snapshot.center
        pendingScale = snapshot.scale
        pendingUpDirectionY = upDirectionY
        gestureStatus = .possible(snapshot)
        return ListenerDecision()
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
        let upwardDelta = pendingUpDirectionY * deltaY
        let dominantMovement = max(abs(deltaX), abs(upwardDelta))
        guard dominantMovement >= activationThreshold else {
            gestureStatus = .possible(snapshot)
            return ListenerDecision(suppressions: activeSuppressions)
        }
        guard upwardDelta >= activationThreshold, upwardDelta >= abs(deltaX) else {
            return cancelGesture(with: snapshot)
        }

        self.pendingCenter = snapshot.center
        pendingScale = snapshot.scale
        gestureStatus = .progressing(snapshot)
        return ListenerDecision(
            claimInteraction: true,
            suppressions: activeSuppressions,
            emittedEvents: [.timerHUDActivationRequested]
        )
    }

    /// Converts progressing two-finger gestures into Timer HUD input events.
    /// - Parameter snapshot: The current progressing gesture snapshot.
    /// - Returns: A claimed decision with optional input and foreground-event suppressions.
    private mutating func receiveTimerInput(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
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
            upDirectionY: pendingUpDirectionY,
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
        return ListenerDecision(
            claimInteraction: true,
            suppressions: suppressions(for: input),
            emittedEvents: [.timerHUDInput(input)]
        )
    }

    /// Suppressions active while a Timer HUD gesture is possible or progressing.
    private var activeSuppressions: Set<SuppressionRequest> {
        withEscapeSuppression([.scroll(axis: .vertical), .scroll(axis: .horizontal)])
    }

    /// Chooses foreground-event suppressions for a classified Timer HUD input.
    /// - Parameter input: The input emitted from gesture classification.
    /// - Returns: Suppressions that match the input axis plus Escape suppression.
    private func suppressions(for input: TimerHUDInput) -> Set<SuppressionRequest> {
        switch input.kind {
        case .scrollUp, .scrollDown:
            return withEscapeSuppression([.scroll(axis: .vertical)])
        case .scrollLeft, .scrollRight:
            return withEscapeSuppression([.scroll(axis: .horizontal)])
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

    /// Whether the Timer HUD is currently visible according to the shared visibility mirror.
    private var isTimerHUDActive: Bool {
        hudVisibilityState?.isActive(TimerHUDDefinition.hudID) ?? false
    }

    /// Determines the normalized upward direction for a bottom-left activation start.
    /// - Parameter center: The normalized contact center.
    /// - Returns: `1` or `-1` for valid activation corners, otherwise `nil`.
    private func upDirectionY(for center: CGPoint) -> CGFloat? {
        guard center.x <= bottomLeftEdgeLimit else { return nil }
        if center.y <= bottomEdgeLimit { return 1 }
        if center.y >= 1 - bottomEdgeLimit { return -1 }
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
        pendingUpDirectionY = 1
    }

    /// Classifies movement since the previous baseline into a Timer HUD input.
    /// - Parameters:
    ///   - center: Previous normalized contact center.
    ///   - pendingScale: Previous aggregate scale value.
    ///   - upDirectionY: Multiplier that normalizes upward motion.
    ///   - snapshot: Current trackpad snapshot to classify.
    /// - Returns: A Timer HUD input when movement exceeds a threshold.
    private func classifyInput(
        from center: CGPoint,
        pendingScale: Double,
        upDirectionY: CGFloat,
        to snapshot: TrackpadSnapshot
    ) -> TimerHUDInput? {
        let deltaX = snapshot.center.x - center.x
        let deltaY = snapshot.center.y - center.y
        let upwardDelta = upDirectionY * deltaY
        let scaleDelta = snapshot.scale - pendingScale

        if abs(scaleDelta) >= pinchThreshold {
            return TimerHUDInput(
                kind: scaleDelta > 0 ? .pinchOut : .pinchIn,
                magnitude: abs(scaleDelta),
                frame: snapshot.frame
            )
        }

        let horizontalMagnitude = abs(deltaX)
        let verticalMagnitude = abs(upwardDelta)
        guard max(horizontalMagnitude, verticalMagnitude) >= scrollThreshold else { return nil }

        let kind: TimerHUDInput.Kind
        let magnitude: Double
        if verticalMagnitude >= horizontalMagnitude {
            kind = upwardDelta >= 0 ? .scrollUp : .scrollDown
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
