import AppKit
import Combine
import Foundation

/// A text-only history of pasteboard changes observed while drift is running.
///
/// macOS exposes the current general pasteboard but not its history, so this store begins recording
/// when the app launches. Entries intentionally stay in memory rather than persisting copied content.
@MainActor
final class ClipboardHistoryStore: ObservableObject {
    @Published private(set) var items: [ClipboardHistoryItem] = []

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount = 0
    private var pollTimer: Timer?

    func start() {
        guard pollTimer == nil else { return }

        lastChangeCount = pasteboard.changeCount
        recordCurrentPasteboard()

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordPasteboardIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func copyToPasteboard(_ item: ClipboardHistoryItem) {
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        record(item.text)
    }

    private func recordPasteboardIfNeeded() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        recordCurrentPasteboard()
    }

    private func recordCurrentPasteboard() {
        guard let text = pasteboard.string(forType: .string) else { return }
        record(text)
    }

    private func record(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0.text == text }
        items.insert(ClipboardHistoryItem(id: UUID(), text: text, capturedAt: Date()), at: 0)
        items = Array(items.prefix(12))
    }
}

/// One text value copied by the user after drift started observing the general pasteboard.
struct ClipboardHistoryItem: Identifiable, Equatable {
    let id: UUID
    let text: String
    let capturedAt: Date

    var systemImage: String {
        URL(string: text)?.scheme == nil ? "doc.on.doc" : "link"
    }
}
