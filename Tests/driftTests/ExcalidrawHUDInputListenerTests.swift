import CoreGraphics
import XCTest
@testable import drift

final class ExcalidrawHUDInputListenerTests: XCTestCase {
    func testDisabledListenerIgnoresActivationGesture() {
        var listener = ExcalidrawHUDInputListener(isEnabled: { false })

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.5, y: 0.99), timestamp: 0, frame: 1))
        let result = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.5, y: 0.7), timestamp: 0.4, frame: 2))

        XCTAssertFalse(result.claimInteraction)
        XCTAssertTrue(result.suppressions.isEmpty)
        XCTAssertTrue(result.emittedEvents.isEmpty)
        if case .waiting = listener.gestureStatus {
        } else {
            XCTFail("Expected the disabled Excalidraw listener to remain idle.")
        }
    }

    @MainActor
    func testFastTopMiddleSwipeOpensQuickDocumentMode() async {
        let hudController = makeHUDController()
        let modeState = ExcalidrawHUDModeState()
        var listener = ExcalidrawHUDInputListener(
            hudController: hudController,
            modeState: modeState
        )

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.5, y: 0.99), timestamp: 0, frame: 1))
        let result = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.5, y: 0.65), timestamp: 0.08, frame: 2))
        await Task.yield()

        XCTAssertTrue(result.claimInteraction)
        XCTAssertTrue(hudController.isActive(ExcalidrawHUDDefinition.hudID))
        XCTAssertEqual(
            hudStore.customStates[ExcalidrawHUDDefinition.hudID.rawValue]?.payload(as: ExcalidrawHUDState.self)?.activation,
            .quickOpen
        )
        guard case .excalidrawHUDDidOpen = result.emittedEvents.first else {
            return XCTFail("Expected Excalidraw HUD open event.")
        }
    }

    @MainActor
    func testHoldTopMiddleSwipeOpensLauncherAndRoutesHorizontalInput() async {
        let hudController = makeHUDController()
        let modeState = ExcalidrawHUDModeState()
        var receivedMessages: [TargetedHUDMessage] = []
        let cancellable = hudMessages.messages.sink { message in
            receivedMessages.append(message)
        }
        var listener = ExcalidrawHUDInputListener(
            hudController: hudController,
            modeState: modeState
        )

        _ = listener.onInteraction(snapshot(.began, center: CGPoint(x: 0.5, y: 0.99), timestamp: 0, frame: 1))
        let opened = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.5, y: 0.82), timestamp: 0.30, frame: 2))
        let moved = listener.onInteraction(snapshot(.changed, center: CGPoint(x: 0.57, y: 0.82), timestamp: 0.36, frame: 3))
        await Task.yield()

        XCTAssertTrue(opened.claimInteraction)
        XCTAssertTrue(moved.claimInteraction)
        XCTAssertEqual(
            hudStore.customStates[ExcalidrawHUDDefinition.hudID.rawValue]?.payload(as: ExcalidrawHUDState.self)?.activation,
            .launcher
        )
        guard case .excalidrawHUDDidReceiveInput(let input) = moved.emittedEvents.first else {
            cancellable.cancel()
            return XCTFail("Expected launcher movement input.")
        }
        XCTAssertEqual(input.kind, .moveRight)
        XCTAssertEqual(receivedMessages.first?.hudID, ExcalidrawHUDDefinition.hudID)
        cancellable.cancel()
    }

    @MainActor
    func testEscapeDoesNotCloseEditorModeButCommandWDoes() {
        let hudController = makeHUDController()
        let modeState = ExcalidrawHUDModeState()
        modeState.setMode(.editor(documentID: "drawing"))
        hudController.open(ExcalidrawHUDDefinition.hudID, source: .testing)
        var listener = ExcalidrawHUDInputListener(
            hudController: hudController,
            modeState: modeState
        )

        let escape = listener.onInteraction(.keyboardPress(keyPress(KeyboardKey.escape)))
        let commandW = listener.onInteraction(.keyboardPress(keyPress(KeyboardKey.w, modifiers: [.command])))

        XCTAssertTrue(escape.suppressions.isEmpty)
        XCTAssertTrue(escape.emittedEvents.isEmpty)
        XCTAssertEqual(commandW.suppressions, [.keyPress(keyCode: KeyboardKey.w)])
        XCTAssertFalse(hudController.isActive(ExcalidrawHUDDefinition.hudID))
        guard case .excalidrawHUDDidClose(let reason) = commandW.emittedEvents.first else {
            return XCTFail("Expected Command-W to close Excalidraw HUD.")
        }
        XCTAssertEqual(reason, .commandW)
    }

    private var hudStore: HUDStore!
    private var hudMessages: HUDMessageBus!

    @MainActor
    private func makeHUDController() -> HUDController {
        let visibilityState = HUDVisibilityState()
        let testingState = HUDTestingState()
        hudStore = HUDStore(visibilityState: visibilityState)
        hudMessages = HUDMessageBus()
        return HUDController(
            hudStore: hudStore,
            hudMessages: hudMessages,
            visibilityState: visibilityState,
            testingState: testingState
        )
    }

    private func snapshot(
        _ phase: TrackpadPhase,
        center: CGPoint,
        timestamp: TimeInterval,
        frame: Int,
        fingerCount: Int = 2
    ) -> TrackpadSnapshot {
        TrackpadSnapshot(
            contacts: phase == .ended ? [] : Array(repeating: contact, count: fingerCount),
            timestamp: timestamp,
            frame: frame,
            phase: phase,
            center: center,
            scale: 1,
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

    private func keyPress(
        _ keyCode: UInt16,
        modifiers: Set<KeyboardModifier> = []
    ) -> KeyboardPressInteraction {
        KeyboardPressInteraction(
            keyCode: keyCode,
            characters: nil,
            modifiers: modifiers
        )
    }
}
