import ApplicationServices
import CoreGraphics
import Foundation

/// Permission snapshot required to install and use a CoreGraphics event tap.
struct EventSuppressionPermissionState: Equatable, Sendable {
    /// Whether the app can listen to hardware input events.
    let hasInputMonitoring: Bool
    /// Whether the app is trusted for Accessibility event control.
    let hasAccessibility: Bool

    /// Whether both permissions required for event-tap handling are present.
    var allowsEventTap: Bool {
        hasInputMonitoring && hasAccessibility
    }
}

/// Applies the current set of typed listener suppression requests to foreground-app events.
final class EventSuppressionController: @unchecked Sendable {
    /// Default cadence for re-checking permissions after prompting the user.
    private static let defaultPermissionCheckInterval: TimeInterval = 0.5

    /// Protects mutable suppression state shared with the event-tap callback.
    private let lock = NSLock()
    /// Supplies the current permission state, injectable for tests.
    private let permissionStateProvider: () -> EventSuppressionPermissionState
    /// Requests any missing permissions, injectable for tests.
    private let permissionRequester: (EventSuppressionPermissionState) -> Void
    /// Interval used by the permission polling timer.
    private let permissionCheckInterval: TimeInterval
    /// Active suppression requests from the listener pipeline.
    private var requests: Set<SuppressionRequest> = []
    /// Mouse-up event types that should be suppressed after their matching button-down was blocked.
    private var suppressedButtonUps: Set<CGEventType> = []
    /// Key codes whose key-up event should be suppressed after a blocked key-down.
    private var suppressedKeyUps: Set<UInt16> = []
    /// Optional receiver used to turn global key-down events into listener suppression requests.
    private var keyboardInteractionReceiver: ((KeyboardPressInteraction) -> Set<SuppressionRequest>)?
    /// Predicate that decides whether an unsuppressed global key-down should be forwarded.
    private var shouldReceiveKeyboardInteraction: ((KeyboardPressInteraction) -> Bool)?
    /// Whether the installed event tap should include keyboard event types.
    private var listensForKeyboardEvents = false
    /// The active CoreGraphics event tap port.
    private var eventTap: CFMachPort?
    /// Run-loop source that keeps the event tap active.
    private var runLoopSource: CFRunLoopSource?
    /// Timer that periodically rechecks permissions after startup.
    private var permissionCheckTimer: Timer?
    /// Whether this controller has already prompted for missing permissions during this run.
    private var didRequestMissingPermissions = false

    /// Creates an event suppression controller.
    /// - Parameters:
    ///   - permissionStateProvider: Closure that returns current Input Monitoring and Accessibility state.
    ///   - permissionRequester: Closure that prompts for missing permissions.
    ///   - permissionCheckInterval: Polling interval used to retry event-tap installation.
    init(
        permissionStateProvider: @escaping () -> EventSuppressionPermissionState = EventSuppressionController.currentPermissionState,
        permissionRequester: @escaping (EventSuppressionPermissionState) -> Void = EventSuppressionController.requestMissingPermissions,
        permissionCheckInterval: TimeInterval = EventSuppressionController.defaultPermissionCheckInterval
    ) {
        self.permissionStateProvider = permissionStateProvider
        self.permissionRequester = permissionRequester
        self.permissionCheckInterval = permissionCheckInterval
    }

    /// Starts permission prompting, permission polling, and event-tap installation.
    /// - Parameters:
    ///   - keyboardInteractionReceiver: Optional callback for forwarding selected key presses to listeners.
    ///   - shouldReceiveKeyboardInteraction: Predicate controlling which global key presses are forwarded.
    /// - Returns: `true` when an event tap is installed and ready.
    func start(
        keyboardInteractionReceiver: ((KeyboardPressInteraction) -> Set<SuppressionRequest>)? = nil,
        shouldReceiveKeyboardInteraction: ((KeyboardPressInteraction) -> Bool)? = nil
    ) -> Bool {
        self.keyboardInteractionReceiver = keyboardInteractionReceiver
        self.shouldReceiveKeyboardInteraction = shouldReceiveKeyboardInteraction
        requestMissingPermissionsOnce()
        startPermissionChecks()
        return refreshTapForCurrentPermissions()
    }

    /// Replaces the active suppression requests used by the event tap.
    /// - Parameter requests: The suppression requests returned by the listener pipeline.
    func update(_ requests: Set<SuppressionRequest>) {
        lock.lock()
        if eventTap == nil {
            self.requests = []
            suppressedButtonUps = []
            suppressedKeyUps = []
        } else {
            self.requests = requests
        }
        lock.unlock()
    }

    /// Stops permission polling, removes the event tap, and clears callback state.
    func stop() {
        stopPermissionChecks()
        terminateTap()
        keyboardInteractionReceiver = nil
        shouldReceiveKeyboardInteraction = nil
        listensForKeyboardEvents = false
        didRequestMissingPermissions = false
    }

    /// Installs an event tap if permissions now allow it, or tears down an invalid tap.
    /// - Returns: `true` when an event tap is available after the refresh.
    @discardableResult
    private func refreshTapForCurrentPermissions() -> Bool {
        guard permissionStateProvider().allowsEventTap else {
            terminateTap()
            return false
        }
        guard eventTap == nil else { return true }
        listensForKeyboardEvents = keyboardInteractionReceiver != nil
        return installTap(at: .cghidEventTap) || installTap(at: .cgSessionEventTap)
    }

    /// Removes the event tap and clears all pending suppression bookkeeping.
    private func terminateTap() {
        clearSuppressionState()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    /// Prompts for missing permissions at most once during a controller run.
    private func requestMissingPermissionsOnce() {
        guard !didRequestMissingPermissions else { return }
        didRequestMissingPermissions = true

        let permissionState = permissionStateProvider()
        guard !permissionState.allowsEventTap else { return }
        permissionRequester(permissionState)
    }

    /// Starts the timer that retries event-tap installation as permissions change.
    private func startPermissionChecks() {
        guard permissionCheckTimer == nil else { return }
        let timer = Timer(timeInterval: permissionCheckInterval, repeats: true) { [weak self] _ in
            _ = self?.refreshTapForCurrentPermissions()
        }
        permissionCheckTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Stops the permission polling timer.
    private func stopPermissionChecks() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

    /// Attempts to install a CoreGraphics event tap at a specific tap location.
    /// - Parameter location: The CoreGraphics event-tap location to try.
    /// - Returns: `true` if the event tap and run-loop source were created.
    private func installTap(at location: CGEventTapLocation) -> Bool {
        var types: [CGEventType] = [
            .scrollWheel,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
        ]
        if listensForKeyboardEvents {
            types.append(contentsOf: [.keyDown, .keyUp])
        }
        let mask = types.reduce(CGEventMask(0)) { mask, type in
            mask | (CGEventMask(1) << type.rawValue)
        }

        guard let tap = CGEvent.tapCreate(
            tap: location,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: suppressionEventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return false
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    /// Clears all active suppression requests and paired-up event tracking.
    private func clearSuppressionState() {
        lock.lock()
        requests = []
        suppressedButtonUps = []
        suppressedKeyUps = []
        lock.unlock()
    }

    /// Filters one event-tap callback event according to the active suppression requests.
    /// - Parameters:
    ///   - type: The CoreGraphics event type.
    ///   - event: The event object to pass through, modify, or suppress.
    /// - Returns: The event to keep, or `nil` to suppress it.
    fileprivate func filter(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard permissionsAllowEventHandling() else {
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown {
            return filterKeyDown(event)
        }
        if type == .keyUp {
            return filterKeyUp(event)
        }

        lock.lock()
        defer { lock.unlock() }

        if type == .scrollWheel {
            return filterScroll(event)
        }

        if let matchingUp = matchingMouseUp(for: type), requests.contains(.press) {
            suppressedButtonUps.insert(matchingUp)
            return nil
        }
        if suppressedButtonUps.remove(type) != nil {
            return nil
        }
        return Unmanaged.passUnretained(event)
    }

    /// Handles key-down events, optionally forwarding them to listeners before deciding suppression.
    /// - Parameter event: The CoreGraphics key-down event.
    /// - Returns: The event to keep, or `nil` to suppress it.
    private func filterKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyPress = KeyboardPressInteraction(event: event)
        let wasAlreadySuppressed = shouldSuppressKeyPress(keyPress.keyCode)
        let listenerSuppressions = shouldForwardKeyDown(keyPress, wasAlreadySuppressed: wasAlreadySuppressed)
            ? keyboardInteractionReceiver?(keyPress) ?? []
            : []
        let shouldSuppress = wasAlreadySuppressed ||
            listenerSuppressions.containsKeyPress(keyPress.keyCode) ||
            shouldSuppressKeyPress(keyPress.keyCode)

        guard shouldSuppress else {
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        suppressedKeyUps.insert(keyPress.keyCode)
        lock.unlock()
        return nil
    }

    /// Suppresses key-up events whose matching key-down was suppressed.
    /// - Parameter event: The CoreGraphics key-up event.
    /// - Returns: The event to keep, or `nil` to suppress it.
    private func filterKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        lock.lock()
        let shouldSuppress = suppressedKeyUps.remove(keyCode) != nil
        lock.unlock()

        return shouldSuppress ? nil : Unmanaged.passUnretained(event)
    }

    /// Applies axis-specific scroll suppression, zeroing one axis when only the other should pass.
    /// - Parameter event: The CoreGraphics scroll-wheel event.
    /// - Returns: The event to keep, modify, or suppress.
    private func filterScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let horizontalDelta = scrollDelta(axis: 2, event: event)
        let verticalDelta = scrollDelta(axis: 1, event: event)
        let suppressHorizontal = shouldSuppress(
            axis: .horizontal,
            delta: horizontalDelta
        )
        let suppressVertical = shouldSuppress(
            axis: .vertical,
            delta: verticalDelta
        )

        guard suppressHorizontal || suppressVertical else {
            return Unmanaged.passUnretained(event)
        }
        if suppressHorizontal { Self.zeroScrollAxis(2, in: event) }
        if suppressVertical { Self.zeroScrollAxis(1, in: event) }

        let remainingHorizontal = suppressHorizontal ? 0 : horizontalDelta
        let remainingVertical = suppressVertical ? 0 : verticalDelta
        return remainingHorizontal == 0 && remainingVertical == 0
            ? nil
            : Unmanaged.passUnretained(event)
    }

    /// Checks whether a scroll delta matches any active scroll suppression request.
    /// - Parameters:
    ///   - axis: The scroll axis being tested.
    ///   - delta: The signed scroll delta for that axis.
    /// - Returns: `true` when that axis and direction should be suppressed.
    private func shouldSuppress(axis: ScrollAxis, delta: Double) -> Bool {
        guard delta != 0 else { return false }
        return requests.contains { request in
            guard case let .scroll(requestAxis, direction) = request,
                  requestAxis == axis else {
                return false
            }
            switch direction {
            case nil: return true
            case .positive: return delta > 0
            case .negative: return delta < 0
            }
        }
    }

    /// Determines whether a key-down event should be forwarded to listener code.
    /// - Parameters:
    ///   - keyPress: The normalized key press.
    ///   - wasAlreadySuppressed: Whether the key is already covered by active suppression requests.
    /// - Returns: `true` when listener code should receive the key press.
    private func shouldForwardKeyDown(
        _ keyPress: KeyboardPressInteraction,
        wasAlreadySuppressed: Bool
    ) -> Bool {
        wasAlreadySuppressed || (shouldReceiveKeyboardInteraction?(keyPress) ?? false)
    }

    /// Checks whether a key code is currently requested for suppression.
    /// - Parameter keyCode: The hardware key code to test.
    /// - Returns: `true` when the key press should be suppressed.
    private func shouldSuppressKeyPress(_ keyCode: UInt16) -> Bool {
        lock.lock()
        let shouldSuppress = requests.contains { request in
            guard case .keyPress(let requestedKeyCode) = request else { return false }
            return requestedKeyCode == keyCode
        }
        lock.unlock()
        return shouldSuppress
    }

    /// Reads the best available scroll delta for a CoreGraphics scroll axis.
    /// - Parameters:
    ///   - axis: CoreGraphics axis number, where `1` is vertical and `2` is horizontal.
    ///   - event: The scroll-wheel event.
    /// - Returns: The signed delta for the requested axis.
    private func scrollDelta(axis: Int, event: CGEvent) -> Double {
        let fixedField: CGEventField = axis == 1
            ? .scrollWheelEventFixedPtDeltaAxis1
            : .scrollWheelEventFixedPtDeltaAxis2
        let pointField: CGEventField = axis == 1
            ? .scrollWheelEventPointDeltaAxis1
            : .scrollWheelEventPointDeltaAxis2
        let integerField: CGEventField = axis == 1
            ? .scrollWheelEventDeltaAxis1
            : .scrollWheelEventDeltaAxis2

        let fixed = event.getDoubleValueField(fixedField)
        if fixed != 0 { return fixed }
        let point = event.getIntegerValueField(pointField)
        if point != 0 { return Double(point) }
        return Double(event.getIntegerValueField(integerField))
    }

    /// Clears all delta fields for one CoreGraphics scroll axis.
    /// - Parameters:
    ///   - axis: CoreGraphics axis number, where `1` is vertical and `2` is horizontal.
    ///   - event: The mutable scroll-wheel event to edit.
    private static func zeroScrollAxis(_ axis: Int, in event: CGEvent) {
        if axis == 1 {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 0)
        } else {
            event.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: 0)
            event.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: 0)
        }
    }

    /// Finds the matching mouse-up event type for a mouse-down event.
    /// - Parameter type: The CoreGraphics mouse event type.
    /// - Returns: The corresponding mouse-up type, if `type` is a button-down event.
    private func matchingMouseUp(for type: CGEventType) -> CGEventType? {
        switch type {
        case .leftMouseDown: .leftMouseUp
        case .rightMouseDown: .rightMouseUp
        case .otherMouseDown: .otherMouseUp
        default: nil
        }
    }

    /// Re-enables the event tap after CoreGraphics disables it because processing took too long.
    fileprivate func enableAfterTapDisabled() {
        guard refreshTapForCurrentPermissions(), let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    /// Handles user-input tap disablement by refreshing permissions and re-enabling the tap.
    fileprivate func disableAfterUserInput() {
        if refreshTapForCurrentPermissions() {
            enableAfterTapDisabled()
        }
    }

    /// Confirms permissions are still valid before handling a callback event.
    /// - Returns: `true` when event handling may continue.
    private func permissionsAllowEventHandling() -> Bool {
        guard permissionStateProvider().allowsEventTap else {
            terminateTap()
            return false
        }
        return true
    }

    /// Reads current macOS permissions required for event suppression.
    /// - Returns: The current permission state.
    private static func currentPermissionState() -> EventSuppressionPermissionState {
        EventSuppressionPermissionState(
            hasInputMonitoring: CGPreflightListenEventAccess(),
            hasAccessibility: AXIsProcessTrusted()
        )
    }

    /// Prompts the user for any missing event-suppression permissions.
    /// - Parameter permissionState: The permission snapshot used to decide which prompts to show.
    private static func requestMissingPermissions(_ permissionState: EventSuppressionPermissionState) {
        if !permissionState.hasInputMonitoring {
            _ = CGRequestListenEventAccess()
        }
        if !permissionState.hasAccessibility {
            let options = [
                "AXTrustedCheckOptionPrompt": true
            ] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }
}

private extension Set where Element == SuppressionRequest {
    /// Checks whether this suppression set contains a key-press request for a key code.
    /// - Parameter keyCode: The hardware key code to test.
    /// - Returns: `true` when the set contains a matching key-press suppression.
    func containsKeyPress(_ keyCode: UInt16) -> Bool {
        contains { request in
            guard case .keyPress(let requestedKeyCode) = request else { return false }
            return requestedKeyCode == keyCode
        }
    }
}

private extension KeyboardPressInteraction {
    /// Creates a normalized keyboard interaction from a CoreGraphics keyboard event.
    /// - Parameter event: The CoreGraphics event to translate.
    init(event: CGEvent) {
        var modifiers = Set<KeyboardModifier>()
        let flags = event.flags

        if flags.contains(.maskCommand) {
            modifiers.insert(.command)
        }
        if flags.contains(.maskControl) {
            modifiers.insert(.control)
        }
        if flags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.maskShift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.maskAlphaShift) {
            modifiers.insert(.capsLock)
        }
        if flags.contains(.maskSecondaryFn) {
            modifiers.insert(.function)
        }

        self.init(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            characters: nil,
            modifiers: modifiers
        )
    }
}

/// CoreGraphics callback that forwards event-tap events to `EventSuppressionController`.
private let suppressionEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventSuppressionController>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout {
        controller.enableAfterTapDisabled()
        return Unmanaged.passUnretained(event)
    }
    if type == .tapDisabledByUserInput {
        controller.disableAfterUserInput()
        return Unmanaged.passUnretained(event)
    }
    return controller.filter(type: type, event: event)
}
