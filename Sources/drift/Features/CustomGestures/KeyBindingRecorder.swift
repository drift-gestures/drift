import AppKit
import SwiftUI

/// Value captured by the reusable key-binding control.
struct KeyBindingValue: Equatable {
    var keyCode: UInt16?
    var modifiers: Set<KeyboardModifier>

    var displayName: String {
        let prefix = KeyboardModifier.displayOrder
            .filter(modifiers.contains)
            .map(\.symbol)
            .joined()
        guard let keyCode else { return prefix.isEmpty ? "Not set" : prefix }
        return prefix + Self.keyName(for: keyCode)
    }

    private static func keyName(for keyCode: UInt16) -> String {
        let commonKeys: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L",
            38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
            45: "N", 46: "M", 47: ".", 50: "`"
        ]
        if let name = commonKeys[keyCode] { return name }
        switch keyCode {
        case 36: return "Return"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            guard let event = NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            ) else { return "Key \(keyCode)" }
            return event.charactersIgnoringModifiers?.uppercased().nonEmpty ?? "Key \(keyCode)"
        }
    }
}

enum KeyBindingRecorderMode {
    case modifiers
    case shortcut
}

/// Click-to-record control shared by activation bindings and keyboard actions.
struct KeyBindingRecorder: View {
    let mode: KeyBindingRecorderMode
    @Binding var value: KeyBindingValue
    var startsRecording = false

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var capturedModifiers: Set<KeyboardModifier> = []

    var body: some View {
        Button(isRecording ? prompt : value.displayName) {
            isRecording ? stopRecording() : startRecording()
        }
        .onAppear {
            if startsRecording { startRecording() }
        }
        .onChange(of: startsRecording) { shouldStartRecording in
            if shouldStartRecording { startRecording() }
        }
        .onDisappear(perform: stopRecording)
    }

    private var prompt: String {
        switch mode {
        case .modifiers: "Hold modifiers, then release"
        case .shortcut: "Press a shortcut"
        }
    }

    private func startRecording() {
        capturedModifiers = []
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { event in
            let modifiers = event.modifierFlags.keyboardModifiers
            switch mode {
            case .modifiers:
                if !modifiers.isEmpty {
                    capturedModifiers.formUnion(modifiers)
                } else if !capturedModifiers.isEmpty {
                    value = KeyBindingValue(keyCode: nil, modifiers: capturedModifiers)
                    stopRecording()
                }
            case .shortcut:
                if event.type == .keyDown {
                    value = KeyBindingValue(keyCode: event.keyCode, modifiers: modifiers)
                    stopRecording()
                }
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        capturedModifiers = []
    }
}

extension KeyboardModifier {
    static let displayOrder: [KeyboardModifier] = [.control, .option, .shift, .command, .function]

    var symbol: String {
        switch self {
        case .command: "⌘"
        case .control: "⌃"
        case .option: "⌥"
        case .shift: "⇧"
        case .capsLock: "⇪"
        case .function: "fn "
        }
    }
}

private extension NSEvent.ModifierFlags {
    var keyboardModifiers: Set<KeyboardModifier> {
        var result: Set<KeyboardModifier> = []
        if contains(.command) { result.insert(.command) }
        if contains(.control) { result.insert(.control) }
        if contains(.option) { result.insert(.option) }
        if contains(.shift) { result.insert(.shift) }
        if contains(.function) { result.insert(.function) }
        return result
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
