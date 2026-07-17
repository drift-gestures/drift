import AppKit
import CoreGraphics
import Foundation

/// Executes the action types supported by saved custom gestures.
enum CustomGestureActionPerformer {
    @MainActor
    static func perform(_ action: CustomGestureAction) {
        switch action {
        case .keyboardShortcut, .keyboardShortcutSequence:
            performKeyboardShortcuts(executionPlan(for: action))
        case .openApplication(let bundleIdentifier):
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        case .openURL:
            guard let url = action.urlToOpen else { return }
            NSWorkspace.shared.open(url)
        case .runScript(let executableURL, let arguments):
            Task.detached {
                let process = Process()
                process.executableURL = executableURL
                process.arguments = arguments
                try? process.run()
            }
        }
    }

    /// Converts persisted shortcut actions into a delay-aware plan. Keeping this separate from
    /// event posting makes sequence order and timing testable without sleeping in tests.
    static func executionPlan(for action: CustomGestureAction) -> [KeyboardShortcutExecutionStep] {
        let shortcuts: [KeyboardShortcut]
        let interStepInterval: TimeInterval
        switch action {
        case .keyboardShortcut(let keyCode, let modifiers):
            shortcuts = [KeyboardShortcut(keyCode: keyCode, modifiers: modifiers)]
            interStepInterval = 0
        case .keyboardShortcutSequence(let steps, let interval):
            shortcuts = steps
            interStepInterval = interval
        case .openApplication, .openURL, .runScript:
            return []
        }

        return shortcuts.enumerated().map { index, shortcut in
            KeyboardShortcutExecutionStep(
                shortcut: shortcut,
                delayBefore: index == 0 ? nil : interStepInterval
            )
        }
    }

    @MainActor
    private static func performKeyboardShortcuts(_ plan: [KeyboardShortcutExecutionStep]) {
        Task { @MainActor in
            let source = CGEventSource(stateID: .hidSystemState)
            await execute(
                plan: plan,
                wait: { delay in
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                },
                performStep: { shortcut in
                keyboardEvents(
                    keyCode: shortcut.keyCode,
                    modifiers: shortcut.modifiers,
                    source: source
                ).forEach { $0.post(tap: .cghidEventTap) }
                }
            )
        }
    }

    /// Executes one complete lifecycle at a time, delaying only before later steps. The injected
    /// collaborators make sequencing verifiable without posting events or sleeping in tests.
    @MainActor
    static func execute(
        plan: [KeyboardShortcutExecutionStep],
        wait: @escaping (TimeInterval) async -> Void,
        performStep: @escaping (KeyboardShortcut) -> Void
    ) async {
        for step in plan {
            if let delay = step.delayBefore, delay > 0 {
                await wait(delay)
            }
            performStep(step.shortcut)
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

struct KeyboardShortcutExecutionStep: Equatable {
    let shortcut: KeyboardShortcut
    /// A delay exists only before a non-initial shortcut step.
    let delayBefore: TimeInterval?
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
