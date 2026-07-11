import AppKit
import SwiftUI

struct ExcalidrawSavePromptContent: View {
    @Binding var title: String
    let focusRequest: Int
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        HStack {
            
            Button {
                cancel()
            } label: {
                Image(systemName: "escape")
                    .font(.system(size: 16))
            }
            .frame(width: 22, height: 22)
            .padding(12)
            .buttonStyle(.plain)
            .cornerRadius(.infinity)
            .background(ClickBlockingView())
            .glassEffect(.regular, in: .rect(cornerRadius: .infinity))
            
            Group {
                SavePromptTextField(
                    title: $title,
                    focusRequest: focusRequest,
                    save: save,
                    cancel: cancel
                )
                .frame(height: 22)
                .frame(maxWidth: .infinity)
            }
            .padding(12)
            .padding([.horizontal], 3)
            .frame(width: ExcalidrawHUDStyle.settingsSize.width)
            .foregroundStyle(.primary)
            .background(ClickBlockingView())
            .glassEffect(.regular, in: .rect(cornerRadius: ExcalidrawHUDStyle.cornerRadius / 1.5))

            Button {
                save()
            } label: {
                Image(systemName: "return")
                    .font(.system(size: 16))
            }
            .frame(width: 22, height: 22)
            .padding(12)
            .buttonStyle(.plain)
            .cornerRadius(.infinity)
            .background(ClickBlockingView())
            .glassEffect(.regular, in: .rect(cornerRadius: .infinity))
        }
    }
}

private struct SavePromptTextField: NSViewRepresentable {
    @Binding var title: String
    let focusRequest: Int
    let save: () -> Void
    let cancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(title: $title, focusRequest: focusRequest, save: save, cancel: cancel)
    }

    func makeNSView(context: Context) -> FirstResponderTextField {
        let textField = FirstResponderTextField()
        textField.delegate = context.coordinator
        textField.stringValue = title
        textField.placeholderString = "Drawing name"
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        textField.textColor = .labelColor
        textField.usesSingleLineMode = true
        textField.onSave = save
        textField.onCancel = cancel
        context.coordinator.requestFocus(for: textField)
        return textField
    }

    func updateNSView(_ textField: FirstResponderTextField, context: Context) {
        context.coordinator.title = $title
        textField.onSave = save
        textField.onCancel = cancel
        if textField.stringValue != title {
            textField.stringValue = title
        }
        if context.coordinator.focusRequest != focusRequest {
            context.coordinator.focusRequest = focusRequest
            context.coordinator.requestFocus(for: textField)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var title: Binding<String>
        var focusRequest: Int
        let save: () -> Void
        let cancel: () -> Void
        private var isHandlingCommand = false
        private var isRequestingFocus = false
        private var hasFocused = false

        init(
            title: Binding<String>,
            focusRequest: Int,
            save: @escaping () -> Void,
            cancel: @escaping () -> Void
        ) {
            self.title = title
            self.focusRequest = focusRequest
            self.save = save
            self.cancel = cancel
        }

        func requestFocus(for textField: FirstResponderTextField) {
            isRequestingFocus = true
            focus(textField)
            DispatchQueue.main.async { [weak self, weak textField] in
                guard let self else { return }
                if let textField {
                    self.focus(textField)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self, weak textField] in
                    guard let self else { return }
                    if let textField {
                        self.focus(textField)
                    }
                    self.isRequestingFocus = false
                }
            }
        }

        private func focus(_ textField: FirstResponderTextField) {
            guard let window = textField.window else { return }
            if window.makeFirstResponder(textField) {
                hasFocused = true
                textField.currentEditor()?.selectAll(nil)
            }
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            title.wrappedValue = textField.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard hasFocused,
                  !isRequestingFocus,
                  !isHandlingCommand
            else {
                return
            }
            cancel()
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                isHandlingCommand = true
                title.wrappedValue = textView.string
                save()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                isHandlingCommand = true
                cancel()
                return true
            default:
                return false
            }
        }
    }
}

private final class FirstResponderTextField: NSTextField {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case KeyboardKey.escape:
            onCancel?()
        case KeyboardKey.return, KeyboardKey.keypadEnter:
            onSave?()
        default:
            super.keyDown(with: event)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let character = event.charactersIgnoringModifiers?.lowercased()
        else {
            return super.performKeyEquivalent(with: event)
        }

        switch character {
        case "a":
            currentEditor()?.selectAll(nil)
            return true
        case "c":
            currentEditor()?.copy(nil)
            return true
        case "v":
            currentEditor()?.paste(nil)
            return true
        case "x":
            currentEditor()?.cut(nil)
            return true
        case "y":
            currentEditor()?.undoManager?.redo()
            return true
        case "z":
            if event.modifierFlags.contains(.shift) {
                currentEditor()?.undoManager?.redo()
            } else {
                currentEditor()?.undoManager?.undo()
            }
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}

private struct ClickBlockingView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ClickBlockingNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private final class ClickBlockingNSView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func otherMouseDown(with event: NSEvent) {}
}
