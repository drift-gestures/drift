import CoreGraphics
import XCTest
@testable import drift

final class CustomGestureTests: XCTestCase {
    func testBasicRotateThresholdCanRequireAHalfTurn() {
        let range = BasicGestureKind.rotate(direction: .clockwise).activationThresholdRange

        XCTAssertEqual(range.upperBound, .pi, accuracy: 0.000_001)
    }

    func testOpenURLActionRoundTripsAndRequiresAScheme() throws {
        let action = CustomGestureAction.openURL(url: " https://example.com/path?source=gesture#details ")

        let decoded = try JSONDecoder().decode(
            CustomGestureAction.self,
            from: JSONEncoder().encode(action)
        )

        XCTAssertEqual(decoded, action)
        XCTAssertEqual(action.urlToOpen?.absoluteString, "https://example.com/path?source=gesture#details")
        XCTAssertNil(CustomGestureAction.openURL(url: "example.com/path").urlToOpen)
        XCTAssertNil(CustomGestureAction.openURL(url: "not a URL").urlToOpen)
    }

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

    func testBasicGestureScopeMatchesAnySelectedApplicationExactly() {
        let gesture = BasicGesture(
            id: UUID(), name: "scoped", kind: .pinch(direction: .outward),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "test"),
            scopedApplicationBundleIdentifiers: ["com.example.editor", "com.example.browser"]
        )

        XCTAssertTrue(gesture.applies(to: "com.example.editor"))
        XCTAssertTrue(gesture.applies(to: "com.example.browser"))
        XCTAssertFalse(gesture.applies(to: "com.example.editor.beta"))
        XCTAssertFalse(gesture.applies(to: nil))
    }

    func testGlobalGestureAppliesWithoutAFocusedApplication() {
        let gesture = BasicGesture(
            id: UUID(), name: "global", kind: .pinch(direction: .outward),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "test")
        )

        XCTAssertTrue(gesture.applies(to: nil))
        XCTAssertTrue(gesture.applies(to: "com.example.anything"))
    }

    func testScopedBasicGestureOverridesMatchingGlobalGesture() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        let global = BasicGesture(
            id: UUID(), name: "global", kind: .edgeSwipe(edge: .bottom, direction: .up),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "global")
        )
        let scoped = BasicGesture(
            id: UUID(), name: "scoped", kind: .edgeSwipe(edge: .bottom, direction: .up),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "scoped"),
            scopedApplicationBundleIdentifiers: ["com.example.editor"]
        )
        store.upsert(global)
        store.upsert(scoped)
        let modeState = CustomGestureModeState(store: store)
        var listener = CustomGestureListener(
            store: store,
            modeState: modeState,
            focusedApplicationBundleIdentifier: { "com.example.editor" }
        )

        _ = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.05, frame: 1, phase: .began))
        let result = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.3, frame: 2, phase: .changed))

        guard case .customGestureRecognized(let id, _, .basic) = result.emittedEvents.first else {
            return XCTFail("Expected a scoped basic gesture")
        }
        XCTAssertEqual(id, scoped.id)
    }

    func testScopedBasicGestureDoesNotRunInAnotherApplication() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        store.upsert(BasicGesture(
            id: UUID(), name: "scoped", kind: .edgeSwipe(edge: .bottom, direction: .up),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "scoped"),
            scopedApplicationBundleIdentifiers: ["com.example.editor"]
        ))
        let modeState = CustomGestureModeState(store: store)
        var listener = CustomGestureListener(
            store: store,
            modeState: modeState,
            focusedApplicationBundleIdentifier: { "com.example.browser" }
        )

        _ = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.05, frame: 1, phase: .began))
        let result = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.3, frame: 2, phase: .changed))

        XCTAssertTrue(result.emittedEvents.isEmpty)
    }

    func testGlobalBasicGestureRunsWhenMatchingAppScopeDoesNotRecognize() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        let scoped = BasicGesture(
            id: UUID(), name: "scoped", kind: .edgeSwipe(edge: .bottom, direction: .left),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "scoped"),
            scopedApplicationBundleIdentifiers: ["com.example.editor"]
        )
        let global = BasicGesture(
            id: UUID(), name: "global", kind: .edgeSwipe(edge: .bottom, direction: .up),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "global")
        )
        store.upsert(scoped)
        store.upsert(global)
        let modeState = CustomGestureModeState(store: store)
        var listener = CustomGestureListener(
            store: store,
            modeState: modeState,
            focusedApplicationBundleIdentifier: { "com.example.editor" }
        )

        _ = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.05, frame: 1, phase: .began))
        let result = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.3, frame: 2, phase: .changed))

        guard case .customGestureRecognized(let id, _, .basic) = result.emittedEvents.first else {
            return XCTFail("Expected the global basic gesture fallback")
        }
        XCTAssertEqual(id, global.id)
    }

    func testBasicGestureUsesApplicationFocusedWhenRecognitionOccurs() throws {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        let recognitionAppGesture = BasicGesture(
            id: UUID(), name: "recognition app", kind: .edgeSwipe(edge: .bottom, direction: .up),
            activationThreshold: 0.2, edgeProximity: 0.1,
            action: .openApplication(bundleIdentifier: "recognition"),
            scopedApplicationBundleIdentifiers: ["com.example.recognition"]
        )
        store.upsert(recognitionAppGesture)
        let modeState = CustomGestureModeState(store: store)
        var focusedApplicationBundleIdentifier = "com.example.start"
        var listener = CustomGestureListener(
            store: store,
            modeState: modeState,
            focusedApplicationBundleIdentifier: { focusedApplicationBundleIdentifier }
        )

        _ = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.05, frame: 1, phase: .began))
        focusedApplicationBundleIdentifier = "com.example.recognition"
        let result = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.3, frame: 2, phase: .changed))

        guard case .customGestureRecognized(let id, _, .basic) = result.emittedEvents.first else {
            return XCTFail("Expected the gesture scoped to the application focused at recognition")
        }
        XCTAssertEqual(id, recognitionAppGesture.id)
    }

    func testAdvancedScopePrefersAcceptedScopedMatchThenFallsBackToGlobal() throws {
        let performedSnapshots = (0..<20).map { index in
            trackpadSnapshot(
                x: Double(index) / 19,
                frame: index,
                phase: index == 0 ? .began : (index == 19 ? .ended : .changed)
            )
        }
        let matchingRecording = try XCTUnwrap(
            AdvancedGestureRecognizer.recording(from: performedSnapshots, positionallyAware: false)
        )
        let wrongSnapshots = (0..<20).map { index in
            trackpadSnapshot(
                x: 0.2,
                y: Double(index) / 19,
                frame: index,
                phase: index == 0 ? .began : .changed
            )
        }
        let wrongRecording = try XCTUnwrap(
            AdvancedGestureRecognizer.recording(from: wrongSnapshots, positionallyAware: false)
        )

        let preferredScoped = AdvancedGesture(
            id: UUID(), name: "scoped", recordings: Array(repeating: matchingRecording, count: 3),
            isPositionallyAware: false, acceptanceThreshold: 0.1,
            action: .openApplication(bundleIdentifier: "scoped"),
            scopedApplicationBundleIdentifiers: ["com.example.editor"]
        )
        let preferredGlobal = AdvancedGesture(
            id: UUID(), name: "global", recordings: Array(repeating: matchingRecording, count: 3),
            isPositionallyAware: false, acceptanceThreshold: 0.1,
            action: .openApplication(bundleIdentifier: "global")
        )
        let preferredID = try XCTUnwrap(recognizedAdvancedGestureID(
            gestures: [preferredGlobal, preferredScoped],
            snapshots: performedSnapshots,
            focusedApplicationBundleIdentifier: "com.example.editor"
        ))
        XCTAssertEqual(preferredID, preferredScoped.id)

        let global = AdvancedGesture(
            id: UUID(), name: "global", recordings: Array(repeating: matchingRecording, count: 3),
            isPositionallyAware: false, acceptanceThreshold: 0.1,
            action: .openApplication(bundleIdentifier: "global")
        )
        let rejectedScoped = AdvancedGesture(
            id: UUID(), name: "scoped", recordings: Array(repeating: wrongRecording, count: 3),
            isPositionallyAware: false, acceptanceThreshold: 0.01,
            action: .openApplication(bundleIdentifier: "scoped"),
            scopedApplicationBundleIdentifiers: ["com.example.editor"]
        )

        let fallbackID = try XCTUnwrap(recognizedAdvancedGestureID(
            gestures: [global, rejectedScoped],
            snapshots: performedSnapshots,
            focusedApplicationBundleIdentifier: "com.example.editor"
        ))

        XCTAssertEqual(fallbackID, global.id)
    }

    func testScopedAdvancedGestureDoesNotRunInAnotherApplication() throws {
        let snapshots = (0..<20).map { index in
            trackpadSnapshot(
                x: Double(index) / 19,
                frame: index,
                phase: index == 0 ? .began : (index == 19 ? .ended : .changed)
            )
        }
        let recording = try XCTUnwrap(
            AdvancedGestureRecognizer.recording(from: snapshots, positionallyAware: false)
        )
        let gesture = AdvancedGesture(
            id: UUID(), name: "scoped", recordings: Array(repeating: recording, count: 3),
            isPositionallyAware: false, acceptanceThreshold: 0.1,
            action: .openApplication(bundleIdentifier: "scoped"),
            scopedApplicationBundleIdentifiers: ["com.example.editor"]
        )

        let recognizedID = try recognizedAdvancedGestureID(
            gestures: [gesture],
            snapshots: snapshots,
            focusedApplicationBundleIdentifier: "com.example.browser"
        )

        XCTAssertNil(recognizedID)
    }

    func testAdvancedScopeChoosesAnAcceptedScopedCandidateBeforeGlobalFallback() throws {
        let performedSnapshots = (0..<20).map { index in
            trackpadSnapshot(
                x: Double(index) / 19,
                frame: index,
                phase: index == 0 ? .began : (index == 19 ? .ended : .changed)
            )
        }
        let closerRejectedSnapshots = (0..<20).map { index in
            let progress = Double(index) / 19
            return trackpadSnapshot(
                x: progress,
                y: 0.45 + 0.02 * progress,
                frame: index,
                phase: index == 0 ? .began : .changed
            )
        }
        let acceptedSnapshots = (0..<20).map { index in
            let progress = Double(index) / 19
            return trackpadSnapshot(
                x: progress,
                y: 0.45 + 0.05 * progress,
                frame: index,
                phase: index == 0 ? .began : .changed
            )
        }
        let performedRecording = try XCTUnwrap(
            AdvancedGestureRecognizer.recording(from: performedSnapshots, positionallyAware: false)
        )
        let closerRejectedRecording = try XCTUnwrap(
            AdvancedGestureRecognizer.recording(from: closerRejectedSnapshots, positionallyAware: false)
        )
        let acceptedRecording = try XCTUnwrap(
            AdvancedGestureRecognizer.recording(from: acceptedSnapshots, positionallyAware: false)
        )
        let global = AdvancedGesture(
            id: UUID(), name: "global", recordings: Array(repeating: performedRecording, count: 3),
            isPositionallyAware: false, acceptanceThreshold: 0.1,
            action: .openApplication(bundleIdentifier: "global")
        )
        let closerRejected = AdvancedGesture(
            id: UUID(), name: "closer", recordings: Array(repeating: closerRejectedRecording, count: 3),
            isPositionallyAware: false, acceptanceThreshold: 0.001,
            action: .openApplication(bundleIdentifier: "closer"),
            scopedApplicationBundleIdentifiers: ["com.example.editor"]
        )
        let accepted = AdvancedGesture(
            id: UUID(), name: "accepted", recordings: Array(repeating: acceptedRecording, count: 3),
            isPositionallyAware: false, acceptanceThreshold: 0.1,
            action: .openApplication(bundleIdentifier: "accepted"),
            scopedApplicationBundleIdentifiers: ["com.example.editor"]
        )

        let recognizedID = try recognizedAdvancedGestureID(
            gestures: [global, closerRejected, accepted],
            snapshots: performedSnapshots,
            focusedApplicationBundleIdentifier: "com.example.editor"
        )

        XCTAssertEqual(recognizedID, accepted.id)
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

    func testSavedGesturesWithoutScopeDecodeAsGlobal() throws {
        struct LegacyBasicGesture: Encodable {
            let id = UUID()
            let name = "basic"
            let kind = BasicGestureKind.pinch(direction: .inward)
            let edgeSegment = EdgeSegment.middle
            let activationThreshold = 0.2
            let edgeProximity = 0.1
            let action = CustomGestureAction.openApplication(bundleIdentifier: "test")
        }
        struct LegacyAdvancedGesture: Encodable {
            let id = UUID()
            let name = "advanced"
            let recordings: [AdvancedGestureRecording] = []
            let isPositionallyAware = false
            let acceptanceThreshold = 0.1
            let action = CustomGestureAction.openApplication(bundleIdentifier: "test")
        }
        struct LegacyLibrary: Encodable {
            let basicGestures = [LegacyBasicGesture()]
            let advancedGestures = [LegacyAdvancedGesture()]
            let advancedActivationModifiers: Set<KeyboardModifier> = [.control]
        }

        let library = try JSONDecoder().decode(
            CustomGestureLibrary.self,
            from: JSONEncoder().encode(LegacyLibrary())
        )

        XCTAssertEqual(library.basicGestures.first?.scopedApplicationBundleIdentifiers, [])
        XCTAssertEqual(library.advancedGestures.first?.scopedApplicationBundleIdentifiers, [])
        XCTAssertTrue(try XCTUnwrap(library.basicGestures.first).applies(to: "com.example.editor"))
        XCTAssertTrue(try XCTUnwrap(library.advancedGestures.first).applies(to: nil))
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

    func testBasicGestureRearmsWhenNextContactBeginsWithoutPreviousEndFrame() throws {
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
        let first = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.3, frame: 2, phase: .changed))
        _ = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.05, frame: 3, phase: .began))
        let second = listener.onInteraction(trackpadSnapshot(x: 0.5, y: 0.3, frame: 4, phase: .changed))

        XCTAssertEqual(first.emittedEvents.count, 1)
        XCTAssertEqual(second.emittedEvents.count, 1)
    }

    func testKeyboardShortcutSequenceReleasesPrimaryKeyAndModifiers() throws {
        let events = CustomGestureActionPerformer.keyboardEvents(
            keyCode: 48,
            modifiers: [.control],
            source: nil
        )

        XCTAssertEqual(events.map { $0.getIntegerValueField(.keyboardEventKeycode) }, [59, 48, 48, 59])
        XCTAssertEqual(
            events.map { $0.type.rawValue },
            [
                CGEventType.flagsChanged.rawValue,
                CGEventType.keyDown.rawValue,
                CGEventType.keyUp.rawValue,
                CGEventType.flagsChanged.rawValue,
            ]
        )
        XCTAssertTrue(events[0].flags.contains(.maskControl))
        XCTAssertTrue(events[2].flags.contains(.maskControl))
        XCTAssertFalse(events[3].flags.contains(.maskControl))
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

    private func recognizedAdvancedGestureID(
        gestures: [AdvancedGesture],
        snapshots: [TrackpadSnapshot],
        focusedApplicationBundleIdentifier: String
    ) throws -> UUID? {
        let suiteName = "CustomGestureTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = CustomGestureStore(defaults: defaults)
        var library = store.snapshot()
        library.advancedGestures = gestures
        store.replace(with: library)
        let modeState = CustomGestureModeState(store: store)
        modeState.update(modifiers: [.control])
        var listener = CustomGestureListener(
            store: store,
            modeState: modeState,
            focusedApplicationBundleIdentifier: { focusedApplicationBundleIdentifier }
        )

        var result = ListenerDecision()
        for snapshot in snapshots {
            result = listener.onInteraction(snapshot)
        }
        guard let event = result.emittedEvents.first else { return nil }
        guard case .customGestureRecognized(let id, _, .advanced) = event else {
            XCTFail("Expected an advanced gesture to be recognized")
            throw NSError(domain: "CustomGestureTests", code: 1)
        }
        return id
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
