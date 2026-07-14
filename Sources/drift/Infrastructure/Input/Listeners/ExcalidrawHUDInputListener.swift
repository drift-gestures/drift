import CoreGraphics
import Foundation

/// Recognizes top-edge Excalidraw HUD activation and launcher navigation gestures.
struct ExcalidrawHUDInputListener: Listener {
    /// Current recognition state used by the listener pipeline.
    var gestureStatus: GestureStatus = .waiting

    private let hudController: HUDController?
    private let modeState: ExcalidrawHUDModeState?
    private let isEnabled: () -> Bool
    private var pendingCenter: CGPoint?
    private var pendingTimestamp: TimeInterval?

    private let activationStartMinY: CGFloat = 0.98
    private let activationStartMinX: CGFloat = 0.34
    private let activationStartMaxX: CGFloat = 0.66
    private let launcherMovementThreshold: CGFloat = 0.05
    private let quickOpenMovementThreshold: CGFloat = 0.3
    private let holdDuration: TimeInterval = 0.3
    private let navigationThreshold: CGFloat = 0.055
    private let executeThreshold: CGFloat = 0.22
    private let searchNavigationThreshold = 0.01
    private let searchScrollSensitivity = 40.0
    
    private var scrollOffset: CGFloat = 0

    /// Creates an Excalidraw HUD listener.
    init(
        hudController: HUDController? = nil,
        modeState: ExcalidrawHUDModeState? = nil,
        isEnabled: @escaping () -> Bool = { true }
    ) {
        self.hudController = hudController
        self.modeState = modeState
        self.isEnabled = isEnabled
    }

    mutating func onInteraction(_ interaction: Interaction) -> ListenerDecision {
        guard isEnabled() else {
            reset()
            return ListenerDecision()
        }
        switch interaction {
        case .clickOutside(let click):
            return onClickOutside(click)
        case .keyboardPress(let keyPress):
            return onKeyboardPress(keyPress)
        case .trackpadSnapshot(let snapshot):
            return onTrackpadSnapshot(snapshot)
        case .modifierStateChanged, .impactEvent:
            return ListenerDecision()
        }
    }

    private mutating func onTrackpadSnapshot(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        if isExcalidrawHUDActive, isSearchMode {
            return receiveSearchInput(snapshot)
        }

        switch gestureStatus {
        case .waiting:
            return checkForActivationStart(snapshot)
        case .possible:
            return checkForActivationProgress(snapshot)
        case .progressing:
            return receiveLauncherInput(snapshot)
        case .cancelled, .ended:
            if snapshot.phase == .ended {
                reset()
            }
            return ListenerDecision()
        }
    }

    private mutating func onKeyboardPress(_ keyPress: KeyboardPressInteraction) -> ListenerDecision {
        if keyPress.keyCode == KeyboardKey.escape {
            return onEscapePress()
        }
        if KeyboardKey.isReturn(keyPress.keyCode) {
            return onReturnPress(keyPress)
        }
        if keyPress.keyCode == KeyboardKey.w,
           keyPress.modifiers.contains(.command),
           isExcalidrawHUDActive {
            guard closeExcalidrawHUD() else { return ListenerDecision() }
            return ListenerDecision(
                suppressions: [.keyPress(keyCode: keyPress.keyCode)],
                emittedEvents: [.excalidrawHUDDidClose(reason: .commandW)]
            )
        }
        if keyPress.keyCode == KeyboardKey.s,
           keyPress.modifiers.contains(.command),
           isExcalidrawHUDActive,
           isEditorMode,
           sendSavePrompt() {
            return ListenerDecision(suppressions: [.keyPress(keyCode: keyPress.keyCode)])
        }
        return ListenerDecision()
    }

    private mutating func onEscapePress() -> ListenerDecision {
        guard isExcalidrawHUDActive,
              !isEditorMode,
              closeExcalidrawHUD()
        else {
            return ListenerDecision()
        }
        return ListenerDecision(
            suppressions: [.keyPress(keyCode: KeyboardKey.escape)],
            emittedEvents: [.excalidrawHUDDidClose(reason: .escape)]
        )
    }

    private func onReturnPress(_ keyPress: KeyboardPressInteraction) -> ListenerDecision {
        guard keyPress.modifiers.isEmpty,
              isExcalidrawHUDActive,
              !isSearchMode,
              !isEditorMode,
              sendDefaultAction()
        else {
            return ListenerDecision()
        }
        return ListenerDecision(suppressions: [.keyPress(keyCode: keyPress.keyCode)])
    }

    private mutating func onClickOutside(_ click: ClickOutsideInteraction) -> ListenerDecision {
        guard click.hudID == ExcalidrawHUDDefinition.hudID else { return ListenerDecision() }
        guard closeExcalidrawHUD() else { return ListenerDecision() }
        return ListenerDecision(emittedEvents: [.excalidrawHUDDidClose(reason: .clickOutside)])
    }

    private mutating func checkForActivationStart(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard !isExcalidrawHUDActive,
              snapshot.fingerCount == 2,
              snapshot.center.y >= activationStartMinY,
              snapshot.center.x >= activationStartMinX,
              snapshot.center.x <= activationStartMaxX
        else {
            return ListenerDecision()
        }

        pendingCenter = snapshot.center
        pendingTimestamp = snapshot.timestamp
        gestureStatus = .possible(snapshot)
        return ListenerDecision()
    }

    private mutating func checkForActivationProgress(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard let pendingCenter,
              let pendingTimestamp
        else {
            return cancelGesture(with: snapshot)
        }

        let deltaY = snapshot.center.y - pendingCenter.y
        let downwardMovement = -deltaY
        let elapsed = snapshot.timestamp - pendingTimestamp

        if snapshot.phase == .ended {
            if downwardMovement >= launcherMovementThreshold {
                return openQuickDocument(from: snapshot, claimInteraction: false)
            }
            reset()
            return ListenerDecision()
        }

        guard downwardMovement >= launcherMovementThreshold else {
            gestureStatus = .possible(snapshot)
            return ListenerDecision(suppressions: activeSuppressions)
        }
        if downwardMovement >= quickOpenMovementThreshold && elapsed < holdDuration {
            return openQuickDocument(from: snapshot, claimInteraction: true)
        }

        if elapsed >= holdDuration {
            self.pendingCenter = snapshot.center
            gestureStatus = .progressing(snapshot)
            guard openExcalidrawHUD(source: .listener, activation: .launcher) else {
                reset()
                return ListenerDecision()
            }
            return ListenerDecision(
                claimInteraction: true,
                suppressions: activeSuppressions,
                emittedEvents: [.excalidrawHUDDidOpen(source: .listener)]
            )
        }

        gestureStatus = .possible(snapshot)
        return ListenerDecision(suppressions: activeSuppressions)
    }

    private mutating func receiveLauncherInput(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard isExcalidrawHUDActive else {
            reset()
            return ListenerDecision()
        }
        guard snapshot.fingerCount == 2 else {
            return ListenerDecision()
        }
        if snapshot.phase == .ended {
            reset()
            return ListenerDecision()
        }
        guard let pendingCenter else {
            self.pendingCenter = snapshot.center
            return ListenerDecision(claimInteraction: true, suppressions: activeSuppressions)
        }

        let deltaX = snapshot.center.x - pendingCenter.x
        let deltaY = snapshot.center.y - pendingCenter.y
        let downwardMovement = -deltaY
        let input: ExcalidrawHUDInput?

        if downwardMovement >= executeThreshold {
            input = ExcalidrawHUDInput(kind: .execute, magnitude: downwardMovement, frame: snapshot.frame)
        } else if abs(deltaX) >= navigationThreshold {
            input = ExcalidrawHUDInput(
                kind: deltaX < 0 ? .moveLeft : .moveRight,
                magnitude: abs(deltaX),
                frame: snapshot.frame
            )
        } else {
            input = nil
        }

        guard let input else {
            gestureStatus = .progressing(snapshot)
            return ListenerDecision(claimInteraction: true, suppressions: activeSuppressions)
        }

        self.pendingCenter = snapshot.center
        guard sendInput(input) else {
            clearTracking()
            return ListenerDecision()
        }

        gestureStatus = .progressing(snapshot)
        return ListenerDecision(
            claimInteraction: true,
            suppressions: activeSuppressions,
            emittedEvents: [.excalidrawHUDDidReceiveInput(input)]
        )
    }

    private mutating func receiveSearchInput(_ snapshot: TrackpadSnapshot) -> ListenerDecision {
        guard snapshot.fingerCount == 2 else {
            return ListenerDecision()
        }

        if snapshot.phase == .ended {
            clearTracking()
            return ListenerDecision()
        }

        guard let pendingCenter else {
            self.pendingCenter = snapshot.center
            return ListenerDecision(claimInteraction: true, suppressions: activeSuppressions)
        }

        let deltaY = snapshot.center.y - pendingCenter.y
        guard abs(deltaY) >= searchNavigationThreshold else {
            return ListenerDecision(claimInteraction: true, suppressions: activeSuppressions)
        }

        self.pendingCenter = snapshot.center
        scrollOffset += -1 * deltaY * searchScrollSensitivity
        if (abs(scrollOffset) >= 1) {
            guard sendSearchScroll(offset: scrollOffset > 0 ? 1 : -1) else {
                clearTracking()
                return ListenerDecision()
            }
            scrollOffset = scrollOffset - (scrollOffset > 0 ? 1 : -1)
        }
        return ListenerDecision(claimInteraction: true, suppressions: activeSuppressions)
    }

    private mutating func openQuickDocument(
        from snapshot: TrackpadSnapshot,
        claimInteraction: Bool
    ) -> ListenerDecision {
        gestureStatus = .ended(snapshot)
        guard openExcalidrawHUD(source: .listener, activation: .quickOpen) else {
            reset()
            return ListenerDecision()
        }
        return ListenerDecision(
            claimInteraction: claimInteraction,
            suppressions: activeSuppressions,
            emittedEvents: [.excalidrawHUDDidOpen(source: .listener)]
        )
    }

    private var activeSuppressions: Set<SuppressionRequest> {
        [
            .scroll(axis: .vertical),
            .scroll(axis: .horizontal),
            .keyPress(keyCode: KeyboardKey.escape),
        ]
    }

    private var isExcalidrawHUDActive: Bool {
        hudController?.isActive(ExcalidrawHUDDefinition.hudID) ?? false
    }

    private var isEditorMode: Bool {
        guard case .editor = modeState?.currentMode else { return false }
        return true
    }

    private var isSearchMode: Bool {
        guard case .search = modeState?.currentMode else { return false }
        return isExcalidrawHUDActive
    }

    private func openExcalidrawHUD(
        source: HUDSessionSource,
        activation: ExcalidrawHUDState.Activation
    ) -> Bool {
        hudController?.open(
            ExcalidrawHUDDefinition.hudID,
            source: source,
            state: HUDState(ExcalidrawHUDState(activation: activation))
        ) ?? true
    }

    private mutating func closeExcalidrawHUD() -> Bool {
        guard let hudController else {
            reset()
            return true
        }
        guard hudController.close(ExcalidrawHUDDefinition.hudID) else { return false }
        reset()
        return true
    }

    private func sendInput(_ input: ExcalidrawHUDInput) -> Bool {
        hudController?.send(.excalidraw(.input(input)), to: ExcalidrawHUDDefinition.hudID) ?? true
    }

    private func sendDefaultAction() -> Bool {
        hudController?.send(.excalidraw(.defaultAction), to: ExcalidrawHUDDefinition.hudID) ?? false
    }

    private func sendSavePrompt() -> Bool {
        hudController?.send(.excalidraw(.savePrompt), to: ExcalidrawHUDDefinition.hudID) ?? false
    }

    private func sendSearchScroll(offset: Int) -> Bool {
        hudController?.send(.excalidraw(.searchScroll(offset: offset)), to: ExcalidrawHUDDefinition.hudID) ?? false
    }

    private mutating func cancelGesture(with snapshot: TrackpadSnapshot) -> ListenerDecision {
        clearTracking()
        gestureStatus = .cancelled(snapshot, reason: .excalidrawHUDGestureRuleBroken)
        return ListenerDecision()
    }

    private mutating func reset() {
        clearTracking()
        gestureStatus = .waiting
    }

    private mutating func clearTracking() {
        pendingCenter = nil
        pendingTimestamp = nil
    }
}

private extension CancellationReason {
    /// Cancellation reason used when Excalidraw activation movement violates the gesture rule.
    static let excalidrawHUDGestureRuleBroken = CancellationReason(
        description: "Excalidraw HUD gesture rule broken"
    )
}
