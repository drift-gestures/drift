import AppKit
import Combine
import Foundation

/// A text-only history of pasteboard changes observed while drift is running.
///
/// macOS exposes the current general pasteboard but not its history, so this store begins recording
/// when the app launches. Entries intentionally stay in memory rather than persisting copied content.
@MainActor
final class ClipboardHistoryStore: ObservableObject {
    /// Newest-first clipboard text entries observed during this app run.
    @Published private(set) var items: [ClipboardHistoryItem] = []

    /// The system general pasteboard being observed.
    private let pasteboard = NSPasteboard.general
    /// Last pasteboard change count processed by the store.
    private var lastChangeCount = 0
    /// Polling timer used because AppKit does not publish pasteboard-change notifications.
    private var pollTimer: Timer?

    /// Starts polling the general pasteboard for text changes.
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

    /// Stops pasteboard polling.
    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    /// Copies an existing history item back to the general pasteboard and promotes it in history.
    /// - Parameter item: The clipboard history item to copy.
    func copyToPasteboard(_ item: ClipboardHistoryItem) {
        pasteboard.clearContents()
        pasteboard.setString(item.text, forType: .string)
        lastChangeCount = pasteboard.changeCount
        record(item.text)
    }

    /// Checks the pasteboard change count and records text if it changed.
    private func recordPasteboardIfNeeded() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        recordCurrentPasteboard()
    }

    /// Reads the current string value from the pasteboard and records it.
    private func recordCurrentPasteboard() {
        guard let text = pasteboard.string(forType: .string) else { return }
        record(text)
    }

    /// Inserts non-empty copied text at the front of history while removing duplicates.
    /// - Parameter text: The text value to record.
    private func record(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        items.removeAll { $0.text == text }
        items.insert(ClipboardHistoryItem(id: UUID(), text: text, capturedAt: Date()), at: 0)
        items = Array(items.prefix(12))
    }
}

/// One text value copied by the user after drift started observing the general pasteboard.
struct ClipboardHistoryItem: Identifiable, Equatable {
    /// Stable identity for SwiftUI rendering.
    let id: UUID
    /// Copied text content.
    let text: String
    /// Time the text was captured by drift.
    let capturedAt: Date

    /// SF Symbol that distinguishes URLs from plain text snippets.
    var systemImage: String {
        URL(string: text)?.scheme == nil ? "doc.on.doc" : "link"
    }
}
