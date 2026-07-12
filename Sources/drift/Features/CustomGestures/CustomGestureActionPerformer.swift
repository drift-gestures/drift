import AppKit
import CoreGraphics
import Foundation

/// Executes the three action types supported by saved custom gestures.
enum CustomGestureActionPerformer {
    @MainActor
    static func perform(_ action: CustomGestureAction) {
        switch action {
        case .keyboardShortcut(let keyCode, let modifiers):
            let source = CGEventSource(stateID: .hidSystemState)
            keyboardEvents(keyCode: keyCode, modifiers: modifiers, source: source).forEach {
                $0.post(tap: .cghidEventTap)
            }
        case .openApplication(let bundleIdentifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        case .runScript(let executableURL, let arguments):
            Task.detached {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                try? process.run()
            }
        }
    }

    /// Produces a complete modifier/key press and release sequence so stateful shortcuts do not
    /// remain in their held-key presentation after the gesture action finishes.
    static func keyboardEvents(
        keyCode: UInt16,
        modifiers: Set<KeyboardModifier>,
        source: CGEventSource? = CGEventSource(stateID: .hidSystemState)
    ) -> [CGEvent] {
        let orderedModifiers = KeyboardModifier.eventOrder.filter(modifiers.contains)
        var flags = CGEventFlags()
        var events: [CGEvent] = []

        for modifier in orderedModifiers {
            flags.insert(modifier.cgEventFlag)
            if let event = keyboardEvent(source: source, keyCode: modifier.keyCode, keyDown: true, flags: flags) {
                events.append(event)
            }
        }
        if let event = keyboardEvent(source: source, keyCode: keyCode, keyDown: true, flags: flags) {
            events.append(event)
        }
        if let event = keyboardEvent(source: source, keyCode: keyCode, keyDown: false, flags: flags) {
            events.append(event)
        }
        for modifier in orderedModifiers.reversed() {
            flags.remove(modifier.cgEventFlag)
            if let event = keyboardEvent(source: source, keyCode: modifier.keyCode, keyDown: false, flags: flags) {
                events.append(event)
            }
        }
        return events
    }

    private static func keyboardEvent(
        source: CGEventSource?,
        keyCode: UInt16,
        keyDown: Bool,
        flags: CGEventFlags
    ) -> CGEvent? {
        let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: keyDown)
        event?.flags = flags
        return event
    }
}

private extension KeyboardModifier {
    static let eventOrder: [KeyboardModifier] = [.control, .option, .shift, .command, .capsLock, .function]

    var cgEventFlag: CGEventFlags {
        switch self {
        case .command: .maskCommand
        case .control: .maskControl
        case .option: .maskAlternate
        case .shift: .maskShift
        case .capsLock: .maskAlphaShift
        case .function: .maskSecondaryFn
        }
    }

    var keyCode: UInt16 {
        switch self {
        case .command: 55
        case .control: 59
        case .option: 58
        case .shift: 56
        case .capsLock: 57
        case .function: 63
        }
    }
}
