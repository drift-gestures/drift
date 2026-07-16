import Foundation

/// The single listener responsible for all user-configured basic and advanced gestures.
struct CustomGestureListener: Listener {
    var gestureStatus: GestureStatus = .waiting
    let listensDuringAdvancedGestureMode = true
    private let store: CustomGestureStore
    private let modeState: CustomGestureModeState
    private let captureState: CustomGestureCaptureState
    private let focusedApplicationBundleIdentifier: () -> String?
    private var snapshots: [TrackpadSnapshot] = []
    private var basicStartSnapshot: TrackpadSnapshot?
    private var basicCandidates: [BasicGesture] = []

    init(
        store: CustomGestureStore,
        modeState: CustomGestureModeState,
        captureState: CustomGestureCaptureState = CustomGestureCaptureState(),
        focusedApplicationBundleIdentifier: @escaping () -> String? = { nil }
    ) {
        self.store = store
        self.modeState = modeState
        self.captureState = captureState
        self.focusedApplicationBundleIdentifier = focusedApplicationBundleIdentifier
    }

    mutating func onInteraction(_ interaction: Interaction) -> ListenerDecision {
        guard case .trackpadSnapshot(let snapshot) = interaction else { return ListenerDecision() }
        if captureState.isActive {
            gestureStatus = snapshot.phase == .ended ? .waiting : .progressing(snapshot)
            return ListenerDecision(stopPropagation: true)
        }
        let focusedApplicationBundleIdentifier = focusedApplicationBundleIdentifier()
        return modeState.isAdvancedModeActive
            ? handleAdvanced(snapshot, focusedApplicationBundleIdentifier: focusedApplicationBundleIdentifier)
            : handleBasic(snapshot, focusedApplicationBundleIdentifier: focusedApplicationBundleIdentifier)
    }

    private mutating func handleAdvanced(
        _ snapshot: TrackpadSnapshot,
        focusedApplicationBundleIdentifier: String?
    ) -> ListenerDecision {
        switch snapshot.phase {
        case .began:
            snapshots = [snapshot]
            gestureStatus = .possible(snapshot)
            return ListenerDecision(stopPropagation: true)
        case .changed:
            snapshots.append(snapshot)
            gestureStatus = .progressing(snapshot)
            return ListenerDecision(stopPropagation: true)
        case .ended:
            snapshots.append(snapshot)
            defer { snapshots.removeAll(keepingCapacity: true) }
            let library = store.snapshot()
            let trainedGestures = library.advancedGestures.filter { (3...5).contains($0.recordings.count) }
            let recording = AdvancedGestureRecognizer.recording(from: snapshots, positionallyAware: true)
            let match = recording.flatMap {
                bestAcceptedAdvancedMatch(
                    recording: $0,
                    gestures: trainedGestures,
                    focusedApplicationBundleIdentifier: focusedApplicationBundleIdentifier
                )
            }
            guard let match else {
                gestureStatus = .cancelled(snapshot, reason: .advancedGestureDidNotMatch)
                return ListenerDecision(stopPropagation: true)
            }
            gestureStatus = .ended(snapshot)
            return ListenerDecision(
                stopPropagation: true,
                emittedEvents: [
                    .customGestureRecognized(
                        id: match.gesture.id,
                        action: match.gesture.action,
                        source: .advanced
                    ),
                ]
            )
        }
    }

    private mutating func handleBasic(
        _ snapshot: TrackpadSnapshot,
        focusedApplicationBundleIdentifier: String?
    ) -> ListenerDecision {
        let gestures = store.snapshot().basicGestures
        guard !gestures.isEmpty else {
            gestureStatus = .waiting
            return ListenerDecision()
        }

        switch gestureStatus {
        case .waiting:
            guard snapshot.phase != .ended, snapshot.fingerCount == 2 else {
                return ListenerDecision()
            }
            let candidates = gestures.filter { canBegin($0, at: snapshot) }
            guard !candidates.isEmpty else { return ListenerDecision() }
            basicStartSnapshot = snapshot
            basicCandidates = candidates
            gestureStatus = .possible(snapshot)
            return ListenerDecision(
                suppressions: activeBasicSuppressions(
                    focusedApplicationBundleIdentifier: focusedApplicationBundleIdentifier
                )
            )
        case .ended, .cancelled:
            let suppressions = activeBasicSuppressions(
                focusedApplicationBundleIdentifier: focusedApplicationBundleIdentifier
            )
            if snapshot.phase == .began {
                resetBasicGesture()
                return handleBasic(
                    snapshot,
                    focusedApplicationBundleIdentifier: focusedApplicationBundleIdentifier
                )
            }
            if snapshot.phase == .ended {
                resetBasicGesture()
            }
            return ListenerDecision(suppressions: suppressions)
        case .possible, .progressing:
            break
        }

        guard let start = basicStartSnapshot else { return ListenerDecision() }
        let applicableCandidates = orderedApplicableGestures(
            basicCandidates,
            focusedApplicationBundleIdentifier: focusedApplicationBundleIdentifier
        )
        if let gesture = applicableCandidates.first(where: { matches($0, from: start, to: snapshot) }) {
            gestureStatus = .ended(snapshot)
            return ListenerDecision(
                stopPropagation: true,
                claimInteraction: snapshot.phase != .ended,
                suppressions: activeBasicSuppressions(
                    focusedApplicationBundleIdentifier: focusedApplicationBundleIdentifier
                ),
                emittedEvents: [
                    .customGestureRecognized(
                        id: gesture.id,
                        action: gesture.action,
                        source: .basic
                    ),
                ]
            )
        }
        if snapshot.phase == .ended {
            let suppressions = activeBasicSuppressions(
                focusedApplicationBundleIdentifier: focusedApplicationBundleIdentifier
            )
            resetBasicGesture()
            return ListenerDecision(suppressions: suppressions)
        } else {
            gestureStatus = .progressing(snapshot)
        }
        return ListenerDecision(
            suppressions: activeBasicSuppressions(
                focusedApplicationBundleIdentifier: focusedApplicationBundleIdentifier
            )
        )
    }

    private func orderedApplicableGestures<Gesture: ApplicationScopedGesture>(
        _ gestures: [Gesture],
        focusedApplicationBundleIdentifier: String?
    ) -> [Gesture] {
        let applicable = gestures.filter { $0.applies(to: focusedApplicationBundleIdentifier) }
        return applicable.filter { $0.isScoped(to: focusedApplicationBundleIdentifier) } +
            applicable.filter(\.isGlobal)
    }

    private func bestAcceptedAdvancedMatch(
        recording: AdvancedGestureRecording,
        gestures: [AdvancedGesture],
        focusedApplicationBundleIdentifier: String?
    ) -> (gesture: AdvancedGesture, distance: Double)? {
        let orderedGroups = [
            gestures.filter { $0.isScoped(to: focusedApplicationBundleIdentifier) },
            gestures.filter(\.isGlobal),
        ]
        for group in orderedGroups {
            if let match = AdvancedGestureRecognizer.bestAcceptedMatch(
                recording: recording,
                gestures: group
            ) {
                return match
            }
        }
        return nil
    }

    /// Keeps only gestures whose geometry can begin from the current contact position.
    private func canBegin(_ gesture: BasicGesture, at snapshot: TrackpadSnapshot) -> Bool {
        switch gesture.kind {
        case .edgeSwipe(let edge, _):
            return startsNear(
                edge,
                segment: gesture.edgeSegment,
                point: snapshot.center,
                proximity: gesture.edgeProximity
            )
        case .pinch, .rotate:
            return true
        }
    }

    /// Suppresses native scrolling only while an edge-swipe candidate owns the contact stream.
    private func activeBasicSuppressions(
        focusedApplicationBundleIdentifier: String?
    ) -> Set<SuppressionRequest> {
        let applicableCandidates = basicCandidates.filter {
            $0.applies(to: focusedApplicationBundleIdentifier)
        }
        guard applicableCandidates.contains(where: {
            if case .edgeSwipe = $0.kind { return true }
            return false
        }) else { return [] }
        return [.scroll(axis: .vertical), .scroll(axis: .horizontal)]
    }

    private mutating func resetBasicGesture() {
        basicStartSnapshot = nil
        basicCandidates.removeAll(keepingCapacity: true)
        gestureStatus = .waiting
    }

    private func matches(_ gesture: BasicGesture, from start: TrackpadSnapshot, to current: TrackpadSnapshot) -> Bool {
        switch gesture.kind {
        case .edgeSwipe(let edge, let direction):
            guard startsNear(
                    edge,
                    segment: gesture.edgeSegment,
                    point: start.center,
                    proximity: gesture.edgeProximity
                  ) else { return false }
            let dx = current.center.x - start.center.x
            let dy = current.center.y - start.center.y
            switch direction {
            case .up: return dy >= gesture.activationThreshold && abs(dy) > abs(dx)
            case .down: return -dy >= gesture.activationThreshold && abs(dy) > abs(dx)
            case .left: return -dx >= gesture.activationThreshold && abs(dx) > abs(dy)
            case .right: return dx >= gesture.activationThreshold && abs(dx) > abs(dy)
            }
        case .pinch(let direction):
            let delta = current.scale - start.scale
            return direction == .outward
                ? delta >= gesture.activationThreshold
                : -delta >= gesture.activationThreshold
        case .rotate(let direction):
            let delta = current.rotation - start.rotation
            return direction == .clockwise
                ? delta >= gesture.activationThreshold
                : -delta >= gesture.activationThreshold
        }
    }

    private func startsNear(
        _ edge: TrackpadEdge,
        segment: EdgeSegment,
        point: CGPoint,
        proximity: Double
    ) -> Bool {
        let isNearEdge = switch edge {
        case .top: point.y >= 1 - proximity
        case .bottom: point.y <= proximity
        case .left: point.x <= proximity
        case .right: point.x >= 1 - proximity
        }
        guard isNearEdge else { return false }
        let position = edge == .top || edge == .bottom ? point.x : point.y
        switch segment {
        case .leading: return position < 1.0 / 3.0
        case .middle: return position >= 1.0 / 3.0 && position <= 2.0 / 3.0
        case .trailing: return position > 2.0 / 3.0
        }
    }
}

extension CancellationReason {
    static let advancedGestureDidNotMatch = CancellationReason(description: "Advanced gesture did not match a saved recording")
}
