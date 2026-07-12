import CoreGraphics
import XCTest
@testable import drift

final class CustomGestureTests: XCTestCase {
    func testAdvancedRecordingIsResampledToFixedSize() {
        let snapshots = (0..<12).map { index in
            trackpadSnapshot(x: Double(index) / 11, frame: index, phase: index == 0 ? .began : .changed)
        }

        let recording = AdvancedGestureRecognizer.recording(from: snapshots, positionallyAware: true)

        XCTAssertEqual(recording?.samples.count, AdvancedGestureRecognizer.sampleCount)
        XCTAssertEqual(recording?.samples.first?.fingerCount, 2)
    }

    func testDTWAcceptsSimilarGesturePerformedAtDifferentSpeed() throws {
        let templateSnapshots = (0..<20).map { index in
            trackpadSnapshot(x: Double(index) / 19, frame: index, phase: index == 0 ? .began : .changed)
        }
        let performedSnapshots = (0..<45).map { index in
            let progress = pow(Double(index) / 44, 1.7)
            return trackpadSnapshot(x: progress, frame: index, phase: index == 0 ? .began : .changed)
        }
        let template = try XCTUnwrap(AdvancedGestureRecognizer.recording(from: templateSnapshots, positionallyAware: false))
        let performed = try XCTUnwrap(AdvancedGestureRecognizer.recording(from: performedSnapshots, positionallyAware: false))
        let gesture = AdvancedGesture(
            id: UUID(), name: "line", recordings: [template], isPositionallyAware: false,
            acceptanceThreshold: 0.1, action: .openApplication(bundleIdentifier: "test")
        )

        let match = AdvancedGestureRecognizer.bestMatch(recording: performed, gestures: [gesture])

        XCTAssertEqual(match?.gesture.id, gesture.id)
        XCTAssertLessThan(match?.distance ?? .infinity, gesture.acceptanceThreshold)
    }

    func testDTWDoesNotRejectSamePathForDifferentReportedVelocity() throws {
        let templateSnapshots = (0..<20).map { index in
            trackpadSnapshot(
                x: Double(index) / 19,
                frame: index,
                phase: index == 0 ? .began : .changed,
                velocityX: 0.01
            )
        }
        let performedSnapshots = (0..<20).map { index in
            trackpadSnapshot(
                x: Double(index) / 19,
                frame: index,
                phase: index == 0 ? .began : .changed,
                velocityX: 0.7
            )
        }
        let template = try XCTUnwrap(AdvancedGestureRecognizer.recording(from: templateSnapshots, positionallyAware: false))
        let performed = try XCTUnwrap(AdvancedGestureRecognizer.recording(from: performedSnapshots, positionallyAware: true))
        let gesture = AdvancedGesture(
            id: UUID(), name: "line", recordings: [template], isPositionallyAware: false,
            acceptanceThreshold: 0.1, action: .openApplication(bundleIdentifier: "test")
        )

        let match = AdvancedGestureRecognizer.bestMatch(recording: performed, gestures: [gesture])

        XCTAssertLessThan(match?.distance ?? .infinity, gesture.acceptanceThreshold)
    }

    func testPositionallyAwareGestureRejectsSameShapeInDifferentArea() throws {
        let templateSnapshots = (0..<20).map { index in
            trackpadSnapshot(
                x: 0.1 + 0.2 * Double(index) / 19,
                y: 0.2,
                frame: index,
                phase: index == 0 ? .began : .changed
            )
        }
        let performedSnapshots = (0..<20).map { index in
            trackpadSnapshot(
                x: 0.6 + 0.2 * Double(index) / 19,
                y: 0.7,
                frame: index,
                phase: index == 0 ? .began : .changed
            )
        }
        let template = try XCTUnwrap(AdvancedGestureRecognizer.recording(from: templateSnapshots, positionallyAware: true))
        let performed = try XCTUnwrap(AdvancedGestureRecognizer.recording(from: performedSnapshots, positionallyAware: true))
        let gesture = AdvancedGesture(
            id: UUID(), name: "placed line", recordings: [template], isPositionallyAware: true,
            acceptanceThreshold: 0.1, action: .openApplication(bundleIdentifier: "test")
        )

        let match = AdvancedGestureRecognizer.bestMatch(recording: performed, gestures: [gesture])

        XCTAssertGreaterThan(match?.distance ?? 0, gesture.acceptanceThreshold)
    }

    func testAdvancedModeSkipsBasicListeners() {
        var advancedMode = true
        let pipeline = ListenerPipeline(
            listeners: [AdvancedModeTestListener(), BasicModeTestListener()],
            isAdvancedGestureModeActive: { advancedMode }
        )

        let advancedResult = pipeline.process(trackpadSnapshot(x: 0, frame: 1, phase: .began))
        advancedMode = false
        let basicResult = pipeline.process(trackpadSnapshot(x: 0, frame: 2, phase: .ended))

        XCTAssertEqual(advancedResult.activities.map(\.listenerName), ["AdvancedModeTestListener"])
        XCTAssertEqual(basicResult.activities.count, 2)
    }

    func testCustomListenerRecognizesConfiguredBasicGestureWithoutActivationKey() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        let gesture = BasicGesture(
            id: UUID(), name: "bottom up", kind: .edgeSwipe(edge: .bottom, direction: .up),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "test")
        )
        store.upsert(gesture)
        let modeState = CustomGestureModeState(store: store)
        var listener = CustomGestureListener(store: store, modeState: modeState)

        _ = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.05, frame: 1, phase: .began))
        let result = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.3, frame: 2, phase: .changed))

        guard case .customGestureRecognized(let id, _, .basic) = result.emittedEvents.first else {
            return XCTFail("Expected configured basic gesture to be recognized")
        }
        XCTAssertEqual(id, gesture.id)
        XCTAssertTrue(result.claimInteraction)
        XCTAssertEqual(
            result.suppressions,
            [.scroll(axis: .vertical), .scroll(axis: .horizontal)]
        )
    }

    func testBasicEdgeSwipeSuppressesFromEligibleStartThroughLift() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        store.upsert(BasicGesture(
            id: UUID(), name: "bottom up", kind: .edgeSwipe(edge: .bottom, direction: .up),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "test")
        ))
        let modeState = CustomGestureModeState(store: store)
        let expected: Set<SuppressionRequest> = [
            .scroll(axis: .vertical), .scroll(axis: .horizontal),
        ]
        let pipeline = ListenerPipeline(
            listeners: [CustomGestureListener(store: store, modeState: modeState)]
        )

        let began = pipeline.process(trackpadSnapshot(x: 0.5, y: 0.05, frame: 1, phase: .began))
        let recognized = pipeline.process(trackpadSnapshot(x: 0.5, y: 0.3, frame: 2, phase: .changed))
        let continued = pipeline.process(trackpadSnapshot(x: 0.5, y: 0.4, frame: 3, phase: .changed))
        let ended = pipeline.process(trackpadSnapshot(x: 0.5, y: 0.4, frame: 4, phase: .ended))

        XCTAssertEqual(began.suppressions, expected)
        XCTAssertEqual(recognized.suppressions, expected)
        XCTAssertTrue(recognized.didClaimInteraction)
        XCTAssertEqual(continued.suppressions, expected)
        XCTAssertEqual(ended.suppressions, expected)
        XCTAssertFalse(ended.didClaimInteraction)
    }

    func testBasicEdgeSwipeDoesNotSuppressAnIneligibleStart() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        store.upsert(BasicGesture(
            id: UUID(), name: "bottom up", kind: .edgeSwipe(edge: .bottom, direction: .up),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "test")
        ))
        let modeState = CustomGestureModeState(store: store)
        var listener = CustomGestureListener(store: store, modeState: modeState)

        let result = listener.onInteraction(
            trackpadSnapshot(x: 0.5, y: 0.5, frame: 1, phase: .began)
        )

        XCTAssertTrue(result.suppressions.isEmpty)
        guard case .waiting = listener.gestureStatus else {
            return XCTFail("Expected an unrelated start to remain unsuppressed")
        }
    }

    func testBasicSwipeChecksTwoFingersOnlyWhenLeavingWaiting() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        let gesture = BasicGesture(
            id: UUID(), name: "bottom up", kind: .edgeSwipe(edge: .bottom, direction: .up),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "test")
        )
        store.upsert(gesture)
        let modeState = CustomGestureModeState(store: store)
        var listener = CustomGestureListener(store: store, modeState: modeState)

        _ = listener.onInteraction(trackpadSnapshot(
            x: 0.5, y: 0.05, frame: 1, phase: .began, fingerCount: 2
        ))
        let result = listener.onInteraction(trackpadSnapshot(
            x: 0.5, y: 0.3, frame: 2, phase: .changed, fingerCount: 1
        ))

        guard case .customGestureRecognized(let id, _, .basic) = result.emittedEvents.first else {
            return XCTFail("Expected an in-progress two-finger swipe to survive a finger-count change")
        }
        XCTAssertEqual(id, gesture.id)
    }

    func testBasicSwipeDoesNotLeaveWaitingUntilTwoFingersArePresent() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        store.upsert(BasicGesture(
            id: UUID(), name: "bottom up", kind: .edgeSwipe(edge: .bottom, direction: .up),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "test")
        ))
        let modeState = CustomGestureModeState(store: store)
        var listener = CustomGestureListener(store: store, modeState: modeState)

        _ = listener.onInteraction(trackpadSnapshot(
            x: 0.5, y: 0.05, frame: 1, phase: .began, fingerCount: 1
        ))
        guard case .waiting = listener.gestureStatus else {
            return XCTFail("Expected one finger to leave the listener waiting")
        }

        _ = listener.onInteraction(trackpadSnapshot(
            x: 0.5, y: 0.05, frame: 2, phase: .changed, fingerCount: 2
        ))
        guard case .possible = listener.gestureStatus else {
            return XCTFail("Expected the listener to become possible when two fingers are present")
        }
    }

    func testAdvancedActivationRequiresEntireModifierCombination() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        var library = store.snapshot()
        library.advancedActivationModifiers = [.control, .option]
        store.replace(with: library)
        let modeState = CustomGestureModeState(store: store)

        modeState.update(modifiers: [.control])
        XCTAssertFalse(modeState.isAdvancedModeActive)
        modeState.update(modifiers: [.control, .option])
        XCTAssertTrue(modeState.isAdvancedModeActive)
        modeState.update(modifiers: [.control, .option, .shift])
        XCTAssertTrue(modeState.isAdvancedModeActive)
    }

    func testAdvancedActivationDismissalLastsUntilRequiredModifierIsReleased() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        var library = store.snapshot()
        library.advancedActivationModifiers = [.control, .option]
        store.replace(with: library)
        let modeState = CustomGestureModeState(store: store)

        modeState.update(modifiers: [.control, .option])
        XCTAssertTrue(modeState.isAdvancedModeActive)

        modeState.suspendUntilModifiersReleased()
        XCTAssertFalse(modeState.isAdvancedModeActive)

        modeState.update(modifiers: [.control, .option, .shift])
        XCTAssertFalse(modeState.isAdvancedModeActive)

        modeState.update(modifiers: [.control])
        modeState.update(modifiers: [.control, .option])
        XCTAssertTrue(modeState.isAdvancedModeActive)
    }

    func testLegacySingleActivationModifierMigratesToModifierSet() throws {
        struct LegacyLibrary: Encodable {
            let basicGestures: [BasicGesture] = []
            let advancedGestures: [AdvancedGesture] = []
            let advancedActivationModifier: KeyboardModifier = .option
        }

        let data = try JSONEncoder().encode(LegacyLibrary())
        let library = try JSONDecoder().decode(CustomGestureLibrary.self, from: data)

        XCTAssertEqual(library.advancedActivationModifiers, [.option])
    }

    func testBasicEdgeSwipeHonorsConfiguredStartSegment() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        let gesture = BasicGesture(
            id: UUID(), name: "top left", kind: .edgeSwipe(edge: .top, direction: .down),
            edgeSegment: .leading, activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "test")
        )
        store.upsert(gesture)
        let modeState = CustomGestureModeState(store: store)
        var listener = CustomGestureListener(store: store, modeState: modeState)

        _ = listener.onInteraction(trackpadSnapshot(x: 0.8, y: 0.97, frame: 1, phase: .began))
        let wrongSegment = listener.onInteraction(trackpadSnapshot(x: 0.8, y: 0.6, frame: 2, phase: .changed))
        XCTAssertTrue(wrongSegment.emittedEvents.isEmpty)
        _ = listener.onInteraction(trackpadSnapshot(x: 0.8, y: 0.6, frame: 3, phase: .ended))

        _ = listener.onInteraction(trackpadSnapshot(x: 0.2, y: 0.97, frame: 4, phase: .began))
        let correctSegment = listener.onInteraction(trackpadSnapshot(x: 0.2, y: 0.6, frame: 5, phase: .changed))
        XCTAssertEqual(correctSegment.emittedEvents.count, 1)
    }

    func testCaptureStatePreventsConfiguredGestureActionEvent() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        store.upsert(BasicGesture(
            id: UUID(), name: "bottom up", kind: .edgeSwipe(edge: .bottom, direction: .up),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "test")
        ))
        let modeState = CustomGestureModeState(store: store)
        let captureState = CustomGestureCaptureState()
        captureState.setActive(true)
        var listener = CustomGestureListener(
            store: store,
            modeState: modeState,
            captureState: captureState
        )

        _ = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.05, frame: 1, phase: .began))
        let result = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.4, frame: 2, phase: .changed))

        XCTAssertTrue(result.stopPropagation)
        XCTAssertTrue(result.emittedEvents.isEmpty)
    }

    @MainActor
    func testRecordingSessionCollectsAtMostFiveExamples() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        let modeState = CustomGestureModeState(store: store)
        modeState.update(modifiers: [.control])
        let captureState = CustomGestureCaptureState()
        let session = CustomGestureRecordingSession(modeState: modeState, captureState: captureState)
        session.beginRecording(positionallyAware: false, existing: [])

        for take in 0..<6 {
            session.receive(trackpadSnapshot(x: 0, frame: take * 3, phase: .began))
            session.receive(trackpadSnapshot(x: 0.5, frame: take * 3 + 1, phase: .changed))
            session.receive(trackpadSnapshot(x: 1, frame: take * 3 + 2, phase: .ended))
        }

        XCTAssertEqual(session.recordings.count, 5)
        session.end()
        XCTAssertFalse(captureState.isActive)
    }

    @MainActor
    func testRecordingSessionMergesSameFrameFingerIdentityBoundary() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        let modeState = CustomGestureModeState(store: store)
        modeState.update(modifiers: [.control])
        let captureState = CustomGestureCaptureState()
        let session = CustomGestureRecordingSession(modeState: modeState, captureState: captureState)
        session.beginRecording(positionallyAware: false, existing: [])

        session.receive(trackpadSnapshot(x: 0, frame: 1, phase: .began))
        session.receive(trackpadSnapshot(x: 0.25, frame: 2, phase: .changed))
        session.receive(trackpadSnapshot(x: 0.4, frame: 3, phase: .ended))
        session.receive(trackpadSnapshot(x: 0.4, frame: 3, phase: .began))
        session.receive(trackpadSnapshot(x: 0.75, frame: 4, phase: .changed))
        session.receive(trackpadSnapshot(x: 1, frame: 5, phase: .ended))

        // Beginning a later take flushes the previous genuine end synchronously.
        session.receive(trackpadSnapshot(x: 0, frame: 10, phase: .began))

        XCTAssertEqual(session.recordings.count, 1)
        session.end()
    }

    private func trackpadSnapshot(
        x: Double,
        y: Double = 0.45,
        frame: Int,
        phase: TrackpadPhase,
        velocityX: Double = 0.02,
        fingerCount: Int = 2
    ) -> TrackpadSnapshot {
        let contacts = (0..<fingerCount).map { identifier in
            FingerContact(
                identifier: identifier, state: 1, fingerID: identifier, handID: 0,
                normalizedPosition: ContactVector(x: x, y: y - 0.05 + Double(identifier) * 0.1),
                normalizedVelocity: ContactVector(x: velocityX, y: 0),
                absolutePosition: ContactVector(x: x, y: 0.4),
                absoluteVelocity: ContactVector(x: velocityX, y: 0), size: 1, angle: 0,
                majorAxis: 1, minorAxis: 1, density: 0.5
            )
        }
        return TrackpadSnapshot(
            contacts: contacts, timestamp: Double(frame), frame: frame, phase: phase,
            center: CGPoint(x: x, y: y), scale: 1, rotation: 0
        )
    }
}

private struct AdvancedModeTestListener: Listener {
    var gestureStatus: GestureStatus = .waiting
    let listensDuringAdvancedGestureMode = true
    mutating func onInteraction(_ interaction: Interaction) -> ListenerDecision { ListenerDecision() }
}

private struct BasicModeTestListener: Listener {
    var gestureStatus: GestureStatus = .waiting
    mutating func onInteraction(_ interaction: Interaction) -> ListenerDecision { ListenerDecision() }
}
