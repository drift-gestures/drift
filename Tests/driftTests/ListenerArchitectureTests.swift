import Combine
import CoreGraphics
import XCTest
@testable import drift

final class ListenerArchitectureTests: XCTestCase {
    func testListenersRunInRegistrationOrderAndCanStopPropagation() {
        let pipeline = ListenerPipeline(listeners: [
            StubListener(decision: ListenerDecision(stopPropagation: true)),
            StubListener(decision: ListenerDecision()),
        ])

        let result = pipeline.process(snapshot(.began))
        XCTAssertEqual(result.activities.count, 1)
    }

    func testClaimCancelsOtherPossibleListeners() {
        let pipeline = ListenerPipeline(listeners: [
            ResettingCandidateListener(),
            StubListener(decision: ListenerDecision(claimInteraction: true)),
        ])

        let result = pipeline.process(snapshot(.began))
        XCTAssertTrue(result.didClaimInteraction)
        XCTAssertTrue(result.activities.contains { activity in
            if case .cancelled = activity.status { return true }
            return false
        })
    }

    func testCancelledListenerStillReceivesEndSnapshotToReset() {
        let pipeline = ListenerPipeline(listeners: [
            ResettingCandidateListener(),
            StubListener(decision: ListenerDecision(claimInteraction: true)),
        ])
        _ = pipeline.process(snapshot(.began))

        let result = pipeline.process(snapshot(.ended))
        XCTAssertTrue(result.activities.contains { activity in
            if case .waiting = activity.status { return true }
            return false
        })
    }

    @MainActor
    func testEscapeEndsClaimedTimerHUDInteraction() {
        let hudController = makeHUDController()
        hudController.open(TimerHUDDefinition.hudID, source: .listener)
        let pipeline = ListenerPipeline(listeners: [
            TimerHUDInputListener(hudController: hudController),
        ])

        _ = pipeline.process(snapshot(.began, center: CGPoint(x: 0.1, y: 0.1), frame: 1))
        _ = pipeline.process(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.31), frame: 2))
        let result = pipeline.process(.keyboardPress(escapePress))

        XCTAssertFalse(result.didClaimInteraction)
        XCTAssertEqual(result.suppressions, [.keyPress(keyCode: KeyboardKey.escape)])
        XCTAssertEqual(result.events.count, 1)
        guard case .timerHUDDidClose = result.events.first else {
            return XCTFail("Expected Escape to close Timer HUD.")
        }
    }

    func testBottomLeftUpSwipeRequestsTimerHUDActivationAndClaimsInteraction() {
        var listener = TimerHUDInputListener()

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.1, y: 0.1), frame: 1))
        let result = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.12, y: 0.31), frame: 2))

        XCTAssertTrue(result.claimInteraction)
        XCTAssertEqual(result.suppressions, suppressingEscape([.scroll(axis: .vertical), .scroll(axis: .horizontal)]))
        XCTAssertEqual(result.emittedEvents.count, 1)
        guard case .timerHUDDidOpen = result.emittedEvents.first else {
            return XCTFail("Expected timer HUD activation request.")
        }
    }

    @MainActor
    func testBottomEdgeUpSwipeFurtherRightOpensPomodoroMode() async {
        let visibilityState = HUDVisibilityState()
        let testingState = HUDTestingState()
        let hudStore = HUDStore(visibilityState: visibilityState)
        let hudMessages = HUDMessageBus()
        let hudController = HUDController(
            hudStore: hudStore,
            hudMessages: hudMessages,
            visibilityState: visibilityState,
            testingState: testingState
        )
        var listener = TimerHUDInputListener(hudController: hudController)

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.2, y: 0.1), frame: 1))
        let result = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.2, y: 0.31), frame: 2))
        await Task.yield()

        XCTAssertTrue(result.claimInteraction)
        XCTAssertTrue(hudController.isActive(TimerHUDDefinition.hudID))
        XCTAssertEqual(
            hudStore.customStates[TimerHUDDefinition.hudID.rawValue]?.payload(as: TimerHUDState.self)?.initialMode,
            .pomodoro
        )
        guard case .timerHUDDidOpen = result.emittedEvents.first else {
            return XCTFail("Expected timer HUD activation request.")
        }
    }

    func testWaitingChangedFrameStartsOnlyActivationPossibility() {
        var listener = TimerHUDInputListener()

        let result = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.1), frame: 1))

        XCTAssertFalse(result.claimInteraction)
        XCTAssertTrue(result.emittedEvents.isEmpty)
        if case .possible = listener.gestureStatus {
        } else {
            XCTFail("Expected waiting listener to record a possible activation gesture.")
        }
    }

    func testUpSwipeAfterActivationEmitsTimerDurationInput() {
        var listener = TimerHUDInputListener()

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.1, y: 0.1), frame: 1))
        _ = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.31), frame: 2))
        let result = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.35), frame: 3))

        XCTAssertTrue(result.claimInteraction)
        XCTAssertEqual(result.suppressions, suppressingEscape([.scroll(axis: .vertical), .scroll(axis: .horizontal)]))
        XCTAssertEqual(result.emittedEvents.count, 1)
        guard case .timerHUDDidReceiveInput(let input) = result.emittedEvents.first else {
            return XCTFail("Expected timer duration input.")
        }
        XCTAssertEqual(input.kind, .scrollUp)
        XCTAssertEqual(input.frame, 3)
    }

    func testCancelledActivationDoesNotRestartUntilEnd() {
        var listener = TimerHUDInputListener()

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.1, y: 0.1), frame: 1))
        let cancelled = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.35, y: 0.11), frame: 2))

        XCTAssertFalse(cancelled.claimInteraction)
        XCTAssertTrue(cancelled.emittedEvents.isEmpty)
        if case .cancelled = listener.gestureStatus {
        } else {
            XCTFail("Expected broken activation movement to cancel the gesture.")
        }

        let blocked = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.31), frame: 3))
        XCTAssertFalse(blocked.claimInteraction)
        XCTAssertTrue(blocked.emittedEvents.isEmpty)

        _ = listener.onInteraction(snapshot(.ended, center: CGPoint(x: 0.1, y: 0.31), frame: 4))
        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.1, y: 0.1), frame: 5))
        let restarted = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.31), frame: 6))

        XCTAssertTrue(restarted.claimInteraction)
        XCTAssertEqual(restarted.emittedEvents.count, 1)
        guard case .timerHUDDidOpen = restarted.emittedEvents.first else {
            return XCTFail("Expected timer HUD activation request after reset.")
        }
    }

    func testScrollAndPinchInputAreIgnoredUntilGestureIsProgressing() {
        var listener = TimerHUDInputListener()

        let waitingResult = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.54, y: 0.5), frame: 1))
        XCTAssertFalse(waitingResult.claimInteraction)
        XCTAssertTrue(waitingResult.emittedEvents.isEmpty)

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.1, y: 0.1), frame: 2))
        let possibleResult = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.1), frame: 3, scale: 1.2))

        XCTAssertFalse(possibleResult.claimInteraction)
        XCTAssertTrue(possibleResult.emittedEvents.isEmpty)
        if case .possible = listener.gestureStatus {
        } else {
            XCTFail("Expected pinch-like input to be ignored while activation is only possible.")
        }
    }

    func testProgressingGestureSendsTimerHUDInput() {
        var listener = TimerHUDInputListener()

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.1, y: 0.1), frame: 1))
        _ = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.31), frame: 2))
        let result = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.14, y: 0.31), frame: 3))

        XCTAssertTrue(result.claimInteraction)
        XCTAssertEqual(result.suppressions, suppressingEscape([.scroll(axis: .vertical), .scroll(axis: .horizontal)]))
        XCTAssertEqual(result.emittedEvents.count, 1)
        guard case .timerHUDDidReceiveInput(let input) = result.emittedEvents.first else {
            return XCTFail("Expected timer HUD input.")
        }
        XCTAssertEqual(input.kind, .scrollRight)
        XCTAssertEqual(input.frame, 3)
    }

    @MainActor
    func testTestingTimerHUDStartsInputWithoutActivationSwipe() {
        let hudController = makeHUDController()
        hudController.open(TimerHUDDefinition.hudID, source: .testing)
        var listener = TimerHUDInputListener(
            hudController: hudController
        )

        let started = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.5, y: 0.5), frame: 1))
        let inputResult = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.54, y: 0.5), frame: 2))

        XCTAssertTrue(started.claimInteraction)
        XCTAssertEqual(started.suppressions, suppressingEscape([.scroll(axis: .vertical), .scroll(axis: .horizontal)]))
        XCTAssertTrue(started.emittedEvents.isEmpty)
        XCTAssertTrue(inputResult.claimInteraction)
        XCTAssertEqual(inputResult.suppressions, suppressingEscape([.scroll(axis: .vertical), .scroll(axis: .horizontal)]))
        XCTAssertEqual(inputResult.emittedEvents.count, 1)
        guard case .timerHUDDidReceiveInput(let input) = inputResult.emittedEvents.first else {
            return XCTFail("Expected visible Timer HUD to receive gesture input.")
        }
        XCTAssertEqual(input.kind, .scrollRight)
        XCTAssertEqual(input.frame, 2)
    }

    @MainActor
    func testVisibleTimerHUDDoesNotStartInputWithoutTestingActivation() {
        let hudController = makeHUDController()
        hudController.open(TimerHUDDefinition.hudID, source: .listener)
        var listener = TimerHUDInputListener(
            hudController: hudController
        )

        let started = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.5, y: 0.5), frame: 1))
        let inputResult = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.54, y: 0.5), frame: 2))

        XCTAssertFalse(started.claimInteraction)
        XCTAssertTrue(started.emittedEvents.isEmpty)
        XCTAssertFalse(inputResult.claimInteraction)
        XCTAssertTrue(inputResult.emittedEvents.isEmpty)
    }

    func testReleasingActivationGestureKeepsTimerHUDListening() {
        var listener = TimerHUDInputListener()

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.1, y: 0.1), frame: 1))
        _ = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.31), frame: 2))
        let result = listener.onInteraction(snapshot(.ended, center: CGPoint(x: 0.1, y: 0.31), frame: 3))

        XCTAssertFalse(result.claimInteraction)
        XCTAssertTrue(result.emittedEvents.isEmpty)
        if case .progressing = listener.gestureStatus {
        } else {
            XCTFail("Expected listener to keep listening after release.")
        }
    }

    func testClickOutsideTimerHUDRequestsCloseAndResetsGesture() {
        var listener = TimerHUDInputListener()

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.1, y: 0.1), frame: 1))
        _ = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.31), frame: 2))
        let result = listener.onInteraction(
            .clickOutside(
                ClickOutsideInteraction(
                    hudID: TimerHUDDefinition.hudID,
                    screenLocation: CGPoint(x: 500, y: 500)
                )
            )
        )

        XCTAssertFalse(result.claimInteraction)
        XCTAssertEqual(result.emittedEvents.count, 1)
        guard case .timerHUDDidClose = result.emittedEvents.first else {
            return XCTFail("Expected timer HUD close request.")
        }
        if case .waiting = listener.gestureStatus {
        } else {
            XCTFail("Expected listener to reset after outside click.")
        }
    }

    @MainActor
    func testClickOutsideVisibleTimerHUDStopsFurtherHeldScrollInput() {
        let hudController = makeHUDController()
        hudController.open(TimerHUDDefinition.hudID, source: .testing)
        let pipeline = ListenerPipeline(listeners: [
            TimerHUDInputListener(
                hudController: hudController
            ),
        ])

        _ = pipeline.process(snapshot(.began, center: CGPoint(x: 0.5, y: 0.5), frame: 1))
        let closeResult = pipeline.process(
            .clickOutside(
                ClickOutsideInteraction(
                    hudID: TimerHUDDefinition.hudID,
                    screenLocation: CGPoint(x: 500, y: 500)
                )
            )
        )
        let heldScrollResult = pipeline.process(snapshot(.changed, center: CGPoint(x: 0.5, y: 0.6), frame: 2))

        XCTAssertEqual(closeResult.events.count, 1)
        guard case .timerHUDDidClose = closeResult.events.first else {
            return XCTFail("Expected timer HUD close request.")
        }
        XCTAssertFalse(hudController.isTesting(TimerHUDDefinition.hudID))
        XCTAssertFalse(hudController.isActive(TimerHUDDefinition.hudID))
        XCTAssertFalse(heldScrollResult.didClaimInteraction)
        XCTAssertTrue(heldScrollResult.events.isEmpty)
        XCTAssertTrue(heldScrollResult.suppressions.isEmpty)
    }

    @MainActor
    func testProgrammaticTimerHUDCloseResetsListenerForNextActivationGesture() {
        let hudController = makeHUDController()
        var listener = TimerHUDInputListener(hudController: hudController)

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.1, y: 0.1), frame: 1))
        let opened = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.31), frame: 2))
        XCTAssertTrue(opened.claimInteraction)
        XCTAssertTrue(hudController.isActive(TimerHUDDefinition.hudID))

        hudController.close(TimerHUDDefinition.hudID)
        let releaseAfterExternalClose = listener.onInteraction(snapshot(.ended, center: CGPoint(x: 0.1, y: 0.31), frame: 3))
        XCTAssertFalse(releaseAfterExternalClose.claimInteraction)
        if case .waiting = listener.gestureStatus {
        } else {
            XCTFail("Expected programmatic HUD close to reset listener to waiting.")
        }

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.1, y: 0.1), frame: 4))
        let reopened = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.31), frame: 5))

        XCTAssertTrue(reopened.claimInteraction)
        XCTAssertTrue(hudController.isActive(TimerHUDDefinition.hudID))
        XCTAssertEqual(reopened.emittedEvents.count, 1)
        guard case .timerHUDDidOpen = reopened.emittedEvents.first else {
            return XCTFail("Expected Timer HUD to reopen after programmatic close.")
        }
    }

    func testEscapeDuringTimerHUDGestureRequestsCloseAndSuppressesKeyPress() {
        var listener = TimerHUDInputListener()

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.1, y: 0.1), frame: 1))
        _ = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.31), frame: 2))
        let result = listener.onInteraction(.keyboardPress(escapePress))

        XCTAssertEqual(result.suppressions, [.keyPress(keyCode: KeyboardKey.escape)])
        XCTAssertEqual(result.emittedEvents.count, 1)
        guard case .timerHUDDidClose = result.emittedEvents.first else {
            return XCTFail("Expected Escape to close Timer HUD.")
        }
        if case .waiting = listener.gestureStatus {
        } else {
            XCTFail("Expected listener to reset after Escape.")
        }
    }

    @MainActor
    func testEscapeClosesVisibleTimerHUDAfterGestureReset() {
        let hudController = makeHUDController()
        hudController.open(TimerHUDDefinition.hudID, source: .testing)
        var listener = TimerHUDInputListener(
            hudController: hudController
        )

        let result = listener.onInteraction(.keyboardPress(escapePress))

        XCTAssertFalse(hudController.isTesting(TimerHUDDefinition.hudID))
        XCTAssertFalse(hudController.isActive(TimerHUDDefinition.hudID))
        XCTAssertEqual(result.suppressions, [.keyPress(keyCode: KeyboardKey.escape)])
        XCTAssertEqual(result.emittedEvents.count, 1)
        guard case .timerHUDDidClose = result.emittedEvents.first else {
            return XCTFail("Expected Escape to close visible Timer HUD.")
        }
    }

    @MainActor
    func testReturnRequestsVisibleTimerHUDDefaultAction() async {
        let visibilityState = HUDVisibilityState()
        let testingState = HUDTestingState()
        let hudStore = HUDStore(visibilityState: visibilityState)
        let hudMessages = HUDMessageBus()
        let hudController = HUDController(
            hudStore: hudStore,
            hudMessages: hudMessages,
            visibilityState: visibilityState,
            testingState: testingState
        )
        var receivedMessages: [TargetedHUDMessage] = []
        let cancellable = hudMessages.messages.sink { message in
            receivedMessages.append(message)
        }
        hudController.open(TimerHUDDefinition.hudID, source: .testing)
        var listener = TimerHUDInputListener(hudController: hudController)

        let result = listener.onInteraction(.keyboardPress(returnPress))
        await Task.yield()

        XCTAssertEqual(result.suppressions, [.keyPress(keyCode: KeyboardKey.return)])
        XCTAssertEqual(receivedMessages.count, 1)
        XCTAssertEqual(receivedMessages.first?.hudID, TimerHUDDefinition.hudID)
        guard case .defaultAction = receivedMessages.first?.message.timerHUDMessage else {
            cancellable.cancel()
            return XCTFail("Expected Return to request the Timer HUD default action.")
        }
        cancellable.cancel()
    }

    @MainActor
    func testModifiedReturnDoesNotRequestTimerHUDDefaultAction() async {
        let visibilityState = HUDVisibilityState()
        let testingState = HUDTestingState()
        let hudStore = HUDStore(visibilityState: visibilityState)
        let hudMessages = HUDMessageBus()
        let hudController = HUDController(
            hudStore: hudStore,
            hudMessages: hudMessages,
            visibilityState: visibilityState,
            testingState: testingState
        )
        var receivedMessages: [TargetedHUDMessage] = []
        let cancellable = hudMessages.messages.sink { message in
            receivedMessages.append(message)
        }
        hudController.open(TimerHUDDefinition.hudID, source: .testing)
        var listener = TimerHUDInputListener(hudController: hudController)

        let result = listener.onInteraction(.keyboardPress(modifiedReturnPress))
        await Task.yield()

        XCTAssertTrue(result.suppressions.isEmpty)
        XCTAssertTrue(receivedMessages.isEmpty)
        cancellable.cancel()
    }

    func testUpSwipeAwayFromBottomLeftDoesNotActivateTimerHUD() {
        var listener = TimerHUDInputListener()

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.5, y: 0.5), frame: 1))
        let result = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.5, y: 0.8), frame: 2))

        XCTAssertFalse(result.claimInteraction)
        XCTAssertTrue(result.emittedEvents.isEmpty)
    }

    func testDownSwipeFromTopLeftDoesNotActivateTimerHUD() {
        var listener = TimerHUDInputListener()

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.1, y: 0.9), frame: 1))
        let result = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.1, y: 0.69), frame: 2))

        XCTAssertFalse(result.claimInteraction)
        XCTAssertTrue(result.emittedEvents.isEmpty)
    }

    func testDownSwipeFromTopRightDoesNotActivateTimerHUD() {
        var listener = TimerHUDInputListener()

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.9, y: 0.9), frame: 1))
        let result = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.9, y: 0.69), frame: 2))

        XCTAssertFalse(result.claimInteraction)
        XCTAssertTrue(result.emittedEvents.isEmpty)
    }

    private func snapshot(
        _ phase: TrackpadPhase,
        center: CGPoint = CGPoint(x: 0.5, y: 0.5),
        frame: Int = 1,
        fingerCount: Int = 2,
        scale: Double = 1
    ) -> TrackpadSnapshot {
        TrackpadSnapshot(
            contacts: phase == .ended ? [] : Array(repeating: contact, count: fingerCount),
            timestamp: phase == .ended ? 0.2 : 0.1,
            frame: frame,
            phase: phase,
            center: center,
            scale: scale,
            rotation: 0
        )
    }

    private var contact: FingerContact {
        FingerContact(
            identifier: 1,
            state: 0,
            fingerID: 1,
            handID: 0,
            normalizedPosition: ContactVector(x: 0.5, y: 0.5),
            normalizedVelocity: ContactVector(x: 0, y: 0),
            absolutePosition: ContactVector(x: 0, y: 0),
            absoluteVelocity: ContactVector(x: 0, y: 0),
            size: 1,
            angle: 0,
            majorAxis: 1,
            minorAxis: 1,
            density: 1
        )
    }

    private var escapePress: KeyboardPressInteraction {
        KeyboardPressInteraction(
            keyCode: KeyboardKey.escape,
            characters: nil,
            modifiers: []
        )
    }

    private var returnPress: KeyboardPressInteraction {
        KeyboardPressInteraction(
            keyCode: KeyboardKey.return,
            characters: "\r",
            modifiers: []
        )
    }

    private var modifiedReturnPress: KeyboardPressInteraction {
        KeyboardPressInteraction(
            keyCode: KeyboardKey.return,
            characters: "\r",
            modifiers: [.shift]
        )
    }

    private func suppressingEscape(_ suppressions: Set<SuppressionRequest>) -> Set<SuppressionRequest> {
        suppressions.union([.keyPress(keyCode: KeyboardKey.escape)])
    }

    @MainActor
    private func makeHUDController() -> HUDController {
        let visibilityState = HUDVisibilityState()
        let testingState = HUDTestingState()
        let hudStore = HUDStore(visibilityState: visibilityState)
        let hudMessages = HUDMessageBus()
        return HUDController(
            hudStore: hudStore,
            hudMessages: hudMessages,
            visibilityState: visibilityState,
            testingState: testingState
        )
    }
}

private struct StubListener: Listener {
    var gestureStatus: GestureStatus = .waiting
    let decision: ListenerDecision

    mutating func onInteraction(_ interaction: Interaction) -> ListenerDecision {
        guard let snapshot = interaction.trackpadSnapshot else { return decision }

        gestureStatus = .progressing(snapshot)
        return decision
    }
}

private struct ResettingCandidateListener: Listener {
    var gestureStatus: GestureStatus = .waiting

    mutating func onInteraction(_ interaction: Interaction) -> ListenerDecision {
        guard let snapshot = interaction.trackpadSnapshot else { return ListenerDecision() }

        if case .cancelled = gestureStatus {
            if snapshot.phase == .ended {
                gestureStatus = .waiting
            }
            return ListenerDecision()
        }
        gestureStatus = .possible(snapshot)
        return ListenerDecision()
    }
}
