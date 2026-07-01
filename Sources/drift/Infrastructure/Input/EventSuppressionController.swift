import ApplicationServices
import CoreGraphics
import Foundation

struct EventSuppressionPermissionState: Equatable, Sendable {
    let hasInputMonitoring: Bool
    let hasAccessibility: Bool

    var allowsEventTap: Bool {
        hasInputMonitoring && hasAccessibility
    }
}

/// Applies the current set of typed listener suppression requests to foreground-app events.
final class EventSuppressionController: @unchecked Sendable {
    private static let defaultPermissionCheckInterval: TimeInterval = 0.5

    private let lock = NSLock()
    private let permissionStateProvider: () -> EventSuppressionPermissionState
    private let permissionRequester: (EventSuppressionPermissionState) -> Void
    private let permissionCheckInterval: TimeInterval
    private var requests: Set<SuppressionRequest> = []
    private var suppressedButtonUps: Set<CGEventType> = []
    private var suppressedKeyUps: Set<UInt16> = []
    private var keyboardInteractionReceiver: ((KeyboardPressInteraction) -> Set<SuppressionRequest>)?
    private var shouldReceiveKeyboardInteraction: ((KeyboardPressInteraction) -> Bool)?
    private var listensForKeyboardEvents = false
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var permissionCheckTimer: Timer?
    private var didRequestMissingPermissions = false

    init(
        permissionStateProvider: @escaping () -> EventSuppressionPermissionState = EventSuppressionController.currentPermissionState,
        permissionRequester: @escaping (EventSuppressionPermissionState) -> Void = EventSuppressionController.requestMissingPermissions,
        permissionCheckInterval: TimeInterval = EventSuppressionController.defaultPermissionCheckInterval
    ) {
        self.permissionStateProvider = permissionStateProvider
        self.permissionRequester = permissionRequester
        self.permissionCheckInterval = permissionCheckInterval
    }

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

    func stop() {
        stopPermissionChecks()
        terminateTap()
        keyboardInteractionReceiver = nil
        shouldReceiveKeyboardInteraction = nil
        listensForKeyboardEvents = false
        didRequestMissingPermissions = false
    }

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

    private func requestMissingPermissionsOnce() {
        guard !didRequestMissingPermissions else { return }
        didRequestMissingPermissions = true

        let permissionState = permissionStateProvider()
        guard !permissionState.allowsEventTap else { return }
        permissionRequester(permissionState)
    }

    private func startPermissionChecks() {
        guard permissionCheckTimer == nil else { return }
        let timer = Timer(timeInterval: permissionCheckInterval, repeats: true) { [weak self] _ in
            _ = self?.refreshTapForCurrentPermissions()
        }
        permissionCheckTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopPermissionChecks() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

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

    private func clearSuppressionState() {
        lock.lock()
        requests = []
        suppressedButtonUps = []
        suppressedKeyUps = []
        lock.unlock()
    }

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

    private func filterKeyUp(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        lock.lock()
        let shouldSuppress = suppressedKeyUps.remove(keyCode) != nil
        lock.unlock()

        return shouldSuppress ? nil : Unmanaged.passUnretained(event)
    }

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

    private func shouldForwardKeyDown(
        _ keyPress: KeyboardPressInteraction,
        wasAlreadySuppressed: Bool
    ) -> Bool {
        wasAlreadySuppressed || (shouldReceiveKeyboardInteraction?(keyPress) ?? false)
    }

    private func shouldSuppressKeyPress(_ keyCode: UInt16) -> Bool {
        lock.lock()
        let shouldSuppress = requests.contains { request in
            guard case .keyPress(let requestedKeyCode) = request else { return false }
            return requestedKeyCode == keyCode
        }
        lock.unlock()
        return shouldSuppress
    }

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

    private func matchingMouseUp(for type: CGEventType) -> CGEventType? {
        switch type {
        case .leftMouseDown: .leftMouseUp
        case .rightMouseDown: .rightMouseUp
        case .otherMouseDown: .otherMouseUp
        default: nil
        }
    }

    fileprivate func enableAfterTapDisabled() {
        guard refreshTapForCurrentPermissions(), let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    fileprivate func disableAfterUserInput() {
        if refreshTapForCurrentPermissions() {
            enableAfterTapDisabled()
        }
    }

    private func permissionsAllowEventHandling() -> Bool {
        guard permissionStateProvider().allowsEventTap else {
            terminateTap()
            return false
        }
        return true
    }

    private static func currentPermissionState() -> EventSuppressionPermissionState {
        EventSuppressionPermissionState(
            hasInputMonitoring: CGPreflightListenEventAccess(),
            hasAccessibility: AXIsProcessTrusted()
        )
    }

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
    func containsKeyPress(_ keyCode: UInt16) -> Bool {
        contains { request in
            guard case .keyPress(let requestedKeyCode) = request else { return false }
            return requestedKeyCode == keyCode
        }
    }
}

private extension KeyboardPressInteraction {
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
