import AppKit
import CoreGraphics
import Foundation

struct TimerHUDInputListener: Listener {
    var gestureStatus: GestureStatus = .waiting

    private let isTimerHUDOpen: @Sendable () -> Bool
    private var pendingCenter: CGPoint?
    private var pendingScale = 1.0
    private var isActivationCandidate = false
    private var isClaimingTimerInteraction = false
    private var verticalDirection: CGFloat = 1

    private let activationThreshold: CGFloat = 0.2
    private let bottomLeftEdgeLimit: CGFloat = 0.2
    private let scrollThreshold = 0.018
    private let pinchThreshold = 0.04

    init(isTimerHUDOpen: @escaping @Sendable () -> Bool) {
        self.isTimerHUDOpen = isTimerHUDOpen
    }

    mutating func onStateChange(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        switch snapshot.phase {
        case .began:
            return beginPotentialTimerGesture(snapshot)

        case .changed:
            guard snapshot.fingerCount == 2 else {
                reset()
                return ListenerDecision()
            }

            if isClaimingTimerInteraction || isTimerHUDOpen() {
                return receiveTimerInput(snapshot)
            }

            if !isActivationCandidate {
                let decision = beginPotentialTimerGesture(snapshot)
                guard isActivationCandidate else { return decision }
            }

            return receiveTimerActivationProgress(snapshot)

        case .ended:
            gestureStatus = .ended(snapshot)
            reset()
            return ListenerDecision()
        }
    }

    private mutating func beginPotentialTimerGesture(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard snapshot.fingerCount == 2 else {
            reset()
            return ListenerDecision()
        }

        let hudOpen = isTimerHUDOpen()
        let activationDirection = bottomLeftActivationDirection(for: snapshot.center)
        guard hudOpen || activationDirection != nil else {
            reset()
            return ListenerDecision()
        }

        pendingCenter = snapshot.center
        pendingScale = snapshot.scale
        isActivationCandidate = !hudOpen
        isClaimingTimerInteraction = false
        verticalDirection = activationDirection ?? 1
        gestureStatus = .possible(snapshot)
        return ListenerDecision()
    }

    private mutating func receiveTimerActivationProgress(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard let pendingCenter else {
            return beginPotentialTimerGesture(snapshot)
        }

        let deltaX = snapshot.center.x - pendingCenter.x
        let deltaY = (snapshot.center.y - pendingCenter.y) * verticalDirection
        guard deltaY >= activationThreshold, deltaY >= abs(deltaX) else {
            gestureStatus = .possible(snapshot)
            return ListenerDecision()
        }

        self.pendingCenter = snapshot.center
        pendingScale = snapshot.scale
        isActivationCandidate = false
        isClaimingTimerInteraction = true
        gestureStatus = .progressing(snapshot)
        return ListenerDecision(
            claimInteraction: true,
            suppressions: [.scroll(axis: .vertical)],
            emittedEvents: [.timerHUDActivationRequested]
        )
    }

    private mutating func receiveTimerInput(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard let pendingCenter else {
            self.pendingCenter = snapshot.center
            pendingScale = snapshot.scale
            gestureStatus = .possible(snapshot)
            return ListenerDecision(
                claimInteraction: isClaimingTimerInteraction,
                suppressions: claimedSuppressions
            )
        }

        guard let input = classifyInput(from: pendingCenter, pendingScale: pendingScale, to: snapshot) else {
            gestureStatus = isClaimingTimerInteraction ? .progressing(snapshot) : .possible(snapshot)
            return ListenerDecision(
                claimInteraction: isClaimingTimerInteraction,
                suppressions: claimedSuppressions
            )
        }

        self.pendingCenter = snapshot.center
        pendingScale = snapshot.scale
        isClaimingTimerInteraction = true
        gestureStatus = .progressing(snapshot)
        return ListenerDecision(
            claimInteraction: true,
            suppressions: suppressions(for: input),
            emittedEvents: [.timerHUDInput(input)]
        )
    }

    private var activeSuppressions: Set<SuppressionRequest> {
        [.scroll(axis: .vertical)]
    }

    private var claimedSuppressions: Set<SuppressionRequest> {
        isClaimingTimerInteraction ? activeSuppressions : []
    }

    private func suppressions(for input: TimerHUDInput) -> Set<SuppressionRequest> {
        switch input.kind {
        case .scrollUp, .scrollDown:
            return [.scroll(axis: .vertical)]
        case .scrollLeft, .scrollRight:
            return [.scroll(axis: .horizontal)]
        case .pinchOut, .pinchIn:
            return []
        }
    }

    private func bottomLeftActivationDirection(for center: CGPoint) -> CGFloat? {
        guard center.x <= bottomLeftEdgeLimit else { return nil }
        if center.y <= bottomLeftEdgeLimit { return 1 }
        if center.y >= 1 - bottomLeftEdgeLimit { return -1 }
        return nil
    }

    private mutating func reset() {
        pendingCenter = nil
        pendingScale = 1.0
        isActivationCandidate = false
        isClaimingTimerInteraction = false
        verticalDirection = 1
        gestureStatus = .waiting
    }

    private func classifyInput(
        from center: CGPoint,
        pendingScale: Double,
        to snapshot: TrackpadSnapshot
    ) -> TimerHUDInput? {
        let deltaX = snapshot.center.x - center.x
        let deltaY = (snapshot.center.y - center.y) * verticalDirection
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
