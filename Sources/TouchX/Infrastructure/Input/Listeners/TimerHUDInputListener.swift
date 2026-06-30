import AppKit
import CoreGraphics
import Foundation

struct TimerHUDInputListener: Listener {
    var gestureStatus: GestureStatus = .waiting

    private var pendingCenter: CGPoint?
    private var pendingScale = 1.0

    private let activationThreshold: CGFloat = 0.1
    private let bottomLeftEdgeLimit: CGFloat = 0.2
    private let bottomEdgeLimit: CGFloat = 0.1
    private let bottomLeftLimit: CGFloat = 0.2
    private let scrollThreshold = 0.018
    private let pinchThreshold = 0.04

    mutating func onStateChange(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        switch gestureStatus {
        case .waiting:
            return checkForTimerActivationStart(snapshot)
        case .possible:
            if (snapshot.phase == .ended) {
                gestureStatus = .cancelled(snapshot, reason: CancellationReason(description: "User released during `.possible` state"))
                reset()
                return ListenerDecision()
            } else {
                return checkForTimerActivationProgress(snapshot)
            }
        case .progressing:
            return receiveTimerInput(snapshot)
        case .cancelled, .ended:
            return ListenerDecision()
        }
    }

    private mutating func checkForTimerActivationStart(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard snapshot.fingerCount == 2,
              checkIfLowEnoughStartPoint(for: snapshot.center)
        else {
            return ListenerDecision()
        }
        pendingCenter = snapshot.center
        pendingScale = snapshot.scale
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
        let deltaY = (snapshot.center.y - pendingCenter.y);
        let dominantMovement = max(abs(deltaX), abs(deltaY))
        guard dominantMovement >= activationThreshold else {
            gestureStatus = .possible(snapshot)
            return ListenerDecision()
        }
        guard deltaY >= activationThreshold, deltaY >= abs(deltaX) else {
            return cancelGesture(with: snapshot)
        }

        self.pendingCenter = snapshot.center
        pendingScale = snapshot.scale
        gestureStatus = .progressing(snapshot)
        return ListenerDecision(
            claimInteraction: true,
            suppressions: [.scroll(axis: .vertical)],
            emittedEvents: [.timerHUDActivationRequested]
        )
    }

    private mutating func receiveTimerInput(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard snapshot.fingerCount == 2 else {
            return ListenerDecision()
        }
    
        if (snapshot.phase == .ended) {
            pendingScale = 1.0
            pendingCenter = nil
            return ListenerDecision()
        }
        if (snapshot.phase == .began || pendingCenter == nil) {
            pendingCenter = snapshot.center
            pendingScale = snapshot.scale
            return ListenerDecision()
        }

        guard let input = classifyInput(from: pendingCenter!, pendingScale: pendingScale, to: snapshot) else {
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
        [.scroll(axis: .vertical)]
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

    private func checkIfLowEnoughStartPoint(for center: CGPoint) -> Bool {
        guard center.x <= bottomLeftEdgeLimit else { return false }
        if center.y >= bottomLeftEdgeLimit { return true }
        return false
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
    }

    private func classifyInput(
        from center: CGPoint,
        pendingScale: Double,
        to snapshot: TrackpadSnapshot
    ) -> TimerHUDInput? {
        let deltaX = snapshot.center.x - center.x
        let deltaY = (snapshot.center.y - center.y)
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
    static let timerHUDGestureRuleBroken = CancellationReason(
        description: "Timer HUD gesture rule broken"
    )
}
