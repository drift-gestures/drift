import CoreGraphics
import Foundation

/// Applies the current set of typed listener suppression requests to foreground-app events.
final class EventSuppressionController {
    private let lock = NSLock()
    private var requests: Set<SuppressionRequest> = []
    private var suppressedButtonUps: Set<CGEventType> = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() -> Bool {
        guard eventTap == nil else { return true }
        return installTap(at: .cghidEventTap) || installTap(at: .cgSessionEventTap)
    }

    func update(_ requests: Set<SuppressionRequest>) {
        lock.lock()
        self.requests = requests
        lock.unlock()
    }

    func stop() {
        update([])
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func installTap(at location: CGEventTapLocation) -> Bool {
        let types: [CGEventType] = [
            .scrollWheel,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
        ]
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

    fileprivate func filter(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
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
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
}

private let suppressionEventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let controller = Unmanaged<EventSuppressionController>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        controller.enableAfterTapDisabled()
        return Unmanaged.passUnretained(event)
    }
    return controller.filter(type: type, event: event)
}
