import ApplicationServices
import CoreGraphics
import Foundation

/// User-visible availability of foreground-event suppression.
enum EventSuppressionStatus: Equatable, Sendable {
    case waitingForPermissions
    case available
    case disabled
}

/// Pure lifecycle policy for event-tap availability and automatic permission monitoring.
struct EventSuppressionLifecycle: Equatable, Sendable {
    private(set) var status: EventSuppressionStatus = .waitingForPermissions

    var shouldPollPermissions: Bool {
        status != .disabled
    }

    mutating func didInstallTap() {
        status = .available
    }

    mutating func observeMissingPermissions() {
        guard status == .available else { return }
        status = .disabled
    }

    mutating func didReceiveTapDisabledNotification() {
        status = .disabled
    }

    mutating func didCompleteManualRetry(installed: Bool) {
        status = installed ? .available : .disabled
    }

    mutating func beginInitialPermissionSetup() {
        status = .waitingForPermissions
    }
}

/// One installed CoreGraphics event-tap session that can be discarded independently.
protocol EventSuppressionTapSession: AnyObject {
    func invalidate()
}

/// Scheduling boundary for automatic permission checks.
protocol EventSuppressionPermissionTimer: AnyObject {
    var isRunning: Bool { get }
    func start(interval: TimeInterval, check: @escaping () -> Void)
    func stop()
}

/// Bridges Foundation's sendable timer callback to the main-run-loop-owned check closure.
private final class EventSuppressionPermissionCheck: @unchecked Sendable {
    private let check: () -> Void

    init(_ check: @escaping () -> Void) {
        self.check = check
    }

    func perform() {
        check()
    }
}

/// Carries one detached tap session to its deferred main-queue invalidation.
private final class DeferredEventSuppressionTapInvalidation: @unchecked Sendable {
    private let session: any EventSuppressionTapSession

    init(session: any EventSuppressionTapSession) {
        self.session = session
    }

    func perform() {
        session.invalidate()
    }
}

/// Main-run-loop permission timer used by the production controller.
private final class RunLoopEventSuppressionPermissionTimer: EventSuppressionPermissionTimer {
    private var timer: Timer?

    var isRunning: Bool {
        timer != nil
    }

    func start(interval: TimeInterval, check: @escaping () -> Void) {
        guard timer == nil else { return }
        let permissionCheck = EventSuppressionPermissionCheck(check)
        let timer = Timer(timeInterval: interval, repeats: true) { _ in
            permissionCheck.perform()
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

/// Owns the CoreGraphics port and run-loop source for one tap installation.
private final class CoreGraphicsEventSuppressionTapSession: EventSuppressionTapSession {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private init?(
        location: CGEventTapLocation,
        listensForKeyboardEvents: Bool,
        userInfo: UnsafeMutableRawPointer
    ) {
        var types: [CGEventType] = [
            .scrollWheel,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
        ]
        if listensForKeyboardEvents {
            types.append(contentsOf: [.keyDown, .keyUp, .flagsChanged])
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
            userInfo: userInfo
        ) else {
            return nil
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return nil
        }

        self.tap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    static func install(
        listensForKeyboardEvents: Bool,
        userInfo: UnsafeMutableRawPointer
    ) -> (any EventSuppressionTapSession)? {
        CoreGraphicsEventSuppressionTapSession(
            location: .cghidEventTap,
            listensForKeyboardEvents: listensForKeyboardEvents,
            userInfo: userInfo
        ) ?? CoreGraphicsEventSuppressionTapSession(
            location: .cgSessionEventTap,
            listensForKeyboardEvents: listensForKeyboardEvents,
            userInfo: userInfo
        )
    }

    func invalidate() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
        runLoopSource = nil
        tap = nil
    }
}

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
    /// Protects lifecycle state read by input and main-run-loop callbacks.
    private let lifecycleLock = NSLock()
    /// Supplies the current permission state, injectable for tests.
    private let permissionStateProvider: () -> EventSuppressionPermissionState
    /// Requests any missing permissions, injectable for tests.
    private let permissionRequester: (EventSuppressionPermissionState) -> Void
    /// Publishes suppression availability to the application layer.
    private let statusReceiver: @MainActor (EventSuppressionStatus) -> Void
    /// Creates one fresh CoreGraphics tap session, injectable at the system boundary for tests.
    private let tapSessionFactory: (Bool, UnsafeMutableRawPointer) -> (any EventSuppressionTapSession)?
    /// Owns automatic permission-check scheduling, injectable at the system boundary for tests.
    private let permissionTimer: any EventSuppressionPermissionTimer
    /// Interval used by the permission polling timer.
    private let permissionCheckInterval: TimeInterval
    /// Safety policy for setup, active suppression, and manual recovery.
    private var lifecycle = EventSuppressionLifecycle()
    /// Prevents repeated `start()` calls from resetting a latched Disabled state.
    private var hasStarted = false
    /// Active suppression requests from the listener pipeline.
    private var requests: Set<SuppressionRequest> = []
    /// Mouse-up event types that should be suppressed after their matching button-down was blocked.
    private var suppressedButtonUps: Set<CGEventType> = []
    /// Key codes whose key-up event should be suppressed after a blocked key-down.
    private var suppressedKeyUps: Set<UInt16> = []
    /// Optional receiver used to turn global key-down events into listener suppression requests.
    private var keyboardInteractionReceiver: ((KeyboardPressInteraction) -> Set<SuppressionRequest>)?
    /// Receiver for modifier-state changes used by advanced-gesture activation.
    private var modifierStateReceiver: ((ModifierStateInteraction) -> Void)?
    /// Predicate that decides whether an unsuppressed global key-down should be forwarded.
    private var shouldReceiveKeyboardInteraction: ((KeyboardPressInteraction) -> Bool)?
    /// Whether the installed event tap should include keyboard event types.
    private var listensForKeyboardEvents = false
    /// The active tap session; detached sessions can be invalidated without touching a replacement.
    private var tapSession: (any EventSuppressionTapSession)?
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
        statusReceiver: @escaping @MainActor (EventSuppressionStatus) -> Void = { _ in },
        tapSessionFactory: ((Bool, UnsafeMutableRawPointer) -> (any EventSuppressionTapSession)?)? = nil,
        permissionTimer: (any EventSuppressionPermissionTimer)? = nil,
        permissionCheckInterval: TimeInterval = EventSuppressionController.defaultPermissionCheckInterval
    ) {
        self.permissionStateProvider = permissionStateProvider
        self.permissionRequester = permissionRequester
        self.statusReceiver = statusReceiver
        self.tapSessionFactory = tapSessionFactory ?? { listensForKeyboardEvents, userInfo in
            CoreGraphicsEventSuppressionTapSession.install(
                listensForKeyboardEvents: listensForKeyboardEvents,
                userInfo: userInfo
            )
        }
        self.permissionTimer = permissionTimer ?? RunLoopEventSuppressionPermissionTimer()
        self.permissionCheckInterval = permissionCheckInterval
    }

    /// Starts permission prompting, permission polling, and event-tap installation.
    /// - Parameters:
    ///   - keyboardInteractionReceiver: Optional callback for forwarding selected key presses to listeners.
    ///   - shouldReceiveKeyboardInteraction: Predicate controlling which global key presses are forwarded.
    /// - Returns: `true` when an event tap is installed and ready.
    func start(
        keyboardInteractionReceiver: ((KeyboardPressInteraction) -> Set<SuppressionRequest>)? = nil,
        shouldReceiveKeyboardInteraction: ((KeyboardPressInteraction) -> Bool)? = nil,
        modifierStateReceiver: ((ModifierStateInteraction) -> Void)? = nil
    ) -> Bool {
        self.keyboardInteractionReceiver = keyboardInteractionReceiver
        self.shouldReceiveKeyboardInteraction = shouldReceiveKeyboardInteraction
        self.modifierStateReceiver = modifierStateReceiver
        if !hasStarted {
            hasStarted = true
            if currentStatus != .disabled {
                updateLifecycle { $0.beginInitialPermissionSetup() }
            }
        }
        guard currentStatus != .disabled else { return false }
        requestMissingPermissionsOnce()
        startPermissionChecks()
        return refreshTapForCurrentPermissions()
    }

    /// Replaces the active suppression requests used by the event tap.
    /// - Parameter requests: The suppression requests returned by the listener pipeline.
    func update(_ requests: Set<SuppressionRequest>) {
        lock.lock()
        if currentStatus != .available || tapSession == nil {
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
        modifierStateReceiver = nil
        shouldReceiveKeyboardInteraction = nil
        listensForKeyboardEvents = false
        didRequestMissingPermissions = false
        hasStarted = false
    }

    /// Installs an event tap if permissions now allow it, or tears down an invalid tap.
    /// - Returns: `true` when an event tap is available after the refresh.
    @discardableResult
    private func refreshTapForCurrentPermissions() -> Bool {
        guard currentStatus != .disabled else { return false }
        let permissionState = permissionStateProvider()
        guard permissionState.allowsEventTap else {
            let status = updateLifecycle { lifecycle in
                lifecycle.observeMissingPermissions()
            }
            if status == .disabled {
                disableSuppressionImmediately()
            } else {
                publishStatus(status)
            }
            return false
        }
        guard tapSession == nil else {
            let status = updateLifecycle { $0.didInstallTap() }
            publishStatus(status)
            return true
        }
        listensForKeyboardEvents = keyboardInteractionReceiver != nil
        let installed = installTap()
        if installed {
            let status = updateLifecycle { $0.didInstallTap() }
            publishStatus(status)
        }
        return installed
    }

    /// Removes the event tap and clears all pending suppression bookkeeping.
    private func terminateTap() {
        clearSuppressionState()
        let session = tapSession
        tapSession = nil
        session?.invalidate()
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
        guard currentShouldPollPermissions, !permissionTimer.isRunning else { return }
        permissionTimer.start(interval: permissionCheckInterval) { [weak self] in
            _ = self?.refreshTapForCurrentPermissions()
        }
    }

    /// Stops the permission polling timer.
    private func stopPermissionChecks() {
        permissionTimer.stop()
    }

    /// Attempts to install one fresh event-tap session.
    /// - Returns: `true` when the session factory created and installed a tap.
    private func installTap() -> Bool {
        guard tapSession == nil else { return true }
        tapSession = tapSessionFactory(
            listensForKeyboardEvents,
            Unmanaged.passUnretained(self).toOpaque()
        )
        return tapSession != nil
    }

    /// Makes one explicit attempt to create a fresh event tap after a safety disablement.
    /// - Returns: `true` when a new tap was installed and permission monitoring resumed.
    @discardableResult
    func retrySuppression() -> Bool {
        guard currentStatus == .disabled else {
            return currentStatus == .available
        }

        stopPermissionChecks()
        terminateTap()

        guard permissionStateProvider().allowsEventTap else {
            let status = updateLifecycle { $0.didCompleteManualRetry(installed: false) }
            publishStatus(status)
            return false
        }

        listensForKeyboardEvents = keyboardInteractionReceiver != nil
        let installed = installTap()
        let status = updateLifecycle { $0.didCompleteManualRetry(installed: installed) }
        publishStatus(status)
        if installed {
            startPermissionChecks()
        }
        return installed
    }

    /// Current foreground-event suppression availability.
    var status: EventSuppressionStatus {
        currentStatus
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
        if type == .flagsChanged {
            modifierStateReceiver?(ModifierStateInteraction(modifiers: event.flags.keyboardModifiers))
            return Unmanaged.passUnretained(event)
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

    /// Latches suppression off when CoreGraphics safety-disables the active tap.
    func handleTapDisabledNotification() {
        updateLifecycle { $0.didReceiveTapDisabledNotification() }
        disableSuppressionAfterEventTapCallback()
    }

    /// Confirms permissions are still valid before handling a callback event.
    /// - Returns: `true` when event handling may continue.
    private func permissionsAllowEventHandling() -> Bool {
        guard currentStatus != .disabled else { return false }
        let permissionState = permissionStateProvider()
        guard permissionState.allowsEventTap else {
            updateLifecycle { $0.observeMissingPermissions() }
            disableSuppressionAfterEventTapCallback()
            return false
        }
        return true
    }

    /// Tears down suppression immediately after a timer observes runtime revocation.
    private func disableSuppressionImmediately() {
        publishStatus(.disabled)
        stopPermissionChecks()
        terminateTap()
    }

    /// Defers tap invalidation until CoreGraphics has returned from the current callback.
    private func disableSuppressionAfterEventTapCallback() {
        publishStatus(.disabled)
        stopPermissionChecks()
        clearSuppressionState()
        let disabledSession = tapSession
        tapSession = nil
        guard let disabledSession else { return }
        let invalidation = DeferredEventSuppressionTapInvalidation(session: disabledSession)
        DispatchQueue.main.async {
            invalidation.perform()
        }
    }

    /// Returns the lifecycle status under synchronization.
    private var currentStatus: EventSuppressionStatus {
        lifecycleLock.lock()
        let status = lifecycle.status
        lifecycleLock.unlock()
        return status
    }

    /// Returns whether lifecycle policy currently permits automatic permission checks.
    private var currentShouldPollPermissions: Bool {
        lifecycleLock.lock()
        let shouldPoll = lifecycle.shouldPollPermissions
        lifecycleLock.unlock()
        return shouldPoll
    }

    /// Mutates lifecycle policy and returns the resulting status.
    @discardableResult
    private func updateLifecycle(
        _ update: (inout EventSuppressionLifecycle) -> Void
    ) -> EventSuppressionStatus {
        lifecycleLock.lock()
        update(&lifecycle)
        let status = lifecycle.status
        lifecycleLock.unlock()
        return status
    }

    /// Delivers a lifecycle status to the main-actor application layer.
    private func publishStatus(_ status: EventSuppressionStatus) {
        Task { @MainActor [statusReceiver] in
            statusReceiver(status)
        }
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

private extension KeyboardPressInteraction {
    /// Creates a normalized keyboard interaction from a CoreGraphics keyboard event.
    /// - Parameter event: The CoreGraphics event to translate.
    init(event: CGEvent) {
        self.init(
            keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
            characters: nil,
            modifiers: event.flags.keyboardModifiers
        )
    }
}

private extension CGEventFlags {
    var keyboardModifiers: Set<KeyboardModifier> {
        var modifiers = Set<KeyboardModifier>()
        if contains(.maskCommand) { modifiers.insert(.command) }
        if contains(.maskControl) { modifiers.insert(.control) }
        if contains(.maskAlternate) { modifiers.insert(.option) }
        if contains(.maskShift) { modifiers.insert(.shift) }
        if contains(.maskAlphaShift) { modifiers.insert(.capsLock) }
        if contains(.maskSecondaryFn) { modifiers.insert(.function) }
        return modifiers
    }
}

/// CoreGraphics callback that forwards event-tap events to `EventSuppressionController`.
private let suppressionEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventSuppressionController>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        controller.handleTapDisabledNotification()
        return Unmanaged.passUnretained(event)
    }
    return controller.filter(type: type, event: event)
}
