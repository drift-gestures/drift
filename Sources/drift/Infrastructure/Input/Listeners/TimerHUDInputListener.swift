import AppKit
import CoreGraphics
import Foundation

struct TimerHUDInputListener: Listener {
    var gestureStatus: GestureStatus = .waiting

    private let hudVisibilityState: HUDVisibilityState?
    private var pendingCenter: CGPoint?
    private var pendingScale = 1.0
    private var pendingUpDirectionY: CGFloat = 1

    private let activationThreshold: CGFloat = 0.1
    private let bottomLeftEdgeLimit: CGFloat = 0.1
    private let bottomEdgeLimit: CGFloat = 0.15
    private let scrollThreshold = 0.01
    private let pinchThreshold = 0.04

    init(hudVisibilityState: HUDVisibilityState? = nil) {
        self.hudVisibilityState = hudVisibilityState
    }

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

    private mutating func onClickOutside(_ click: ClickOutsideInteraction) -> ListenerDecision {
        guard click.hudID == TimerHUDDefinition.hudID else { return ListenerDecision() }

        reset()
        return ListenerDecision(emittedEvents: [.timerHUDCloseRequested])
    }

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

    private var activeSuppressions: Set<SuppressionRequest> {
        withEscapeSuppression([.scroll(axis: .vertical), .scroll(axis: .horizontal)])
    }

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

    private func withEscapeSuppression(_ suppressions: Set<SuppressionRequest>) -> Set<SuppressionRequest> {
        suppressions.union([.keyPress(keyCode: KeyboardKey.escape)])
    }

    private var isTimerHUDActive: Bool {
        hudVisibilityState?.isActive(TimerHUDDefinition.hudID) ?? false
    }

    private func upDirectionY(for center: CGPoint) -> CGFloat? {
        guard center.x <= bottomLeftEdgeLimit else { return nil }
        if center.y <= bottomEdgeLimit { return 1 }
        if center.y >= 1 - bottomEdgeLimit { return -1 }
        return nil
    }

    private mutating func cancelGesture(with snapshot: TrackpadSnapshot) -> ListenerDecision {
        clearTracking()
        gestureStatus = .cancelled(snapshot, reason: .timerHUDGestureRuleBroken)
        return ListenerDecision()
    }

    private mutating func reset() {
        clearTracking()
        gestureStatus = .waiting
    }

    private mutating func clearTracking() {
        pendingCenter = nil
        pendingScale = 1.0
        pendingUpDirectionY = 1
    }

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
    static let timerHUDGestureRuleBroken = CancellationReason(
        description: "Timer HUD gesture rule broken"
    )
}
