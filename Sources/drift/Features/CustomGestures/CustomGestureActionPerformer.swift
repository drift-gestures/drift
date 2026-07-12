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
            let flags = modifiers.cgEventFlags
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false)
            down?.flags = flags
            up?.flags = flags
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
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
}

private extension Set where Element == KeyboardModifier {
    var cgEventFlags: CGEventFlags {
        reduce(into: CGEventFlags()) { flags, modifier in
            switch modifier {
            case .command: flags.insert(.maskCommand)
            case .control: flags.insert(.maskControl)
            case .option: flags.insert(.maskAlternate)
            case .shift: flags.insert(.maskShift)
            case .capsLock: flags.insert(.maskAlphaShift)
            case .function: flags.insert(.maskSecondaryFn)
            }
        }
    }
}
