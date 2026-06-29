import SwiftUI

/// Geometry and reading direction for a surface placed near the cursor without leaving its display.
struct OverlaySurfacePlacement {
    var center: CGPoint
    var horizontalFlow: MasonryHorizontalFlow
    var verticalFlow: MasonryVerticalFlow
}

/// Determines which display edge the masonry content grows away from.
enum MasonryHorizontalFlow: Equatable {
    case leftToRight
    case rightToLeft
}

/// Determines whether content is anchored above or below the cursor.
enum MasonryVerticalFlow: Equatable {
    case topToBottom
    case bottomToTop
}

/// The two sections selected by the edge-swipe progress.
enum QuickActionSection: String, CaseIterable, Identifiable {
    case clipboard
    case emoji

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clipboard: "Clipboard"
        case .emoji: "Emoji"
        }
    }

    var systemImage: String {
        switch self {
        case .clipboard: "clipboard.fill"
        case .emoji: "face.smiling.fill"
        }
    }

    var items: [QuickActionItem] {
        switch self {
        case .clipboard:
            // Clipboard content comes from `ClipboardHistoryStore`, not this static section model.
            []
        case .emoji:
            (0..<42).map { _ in QuickActionItem(title: "😁", subtitle: "", systemImage: "") }
        }
    }
}

/// A display item shared by the clipboard and emoji prototype views.
struct QuickActionItem: Identifiable {
    let id = UUID()
    var title: String
    var subtitle: String
    var systemImage: String
}

/// A precomputed layout used because the cards must mirror and reverse with overlay placement.
struct MasonryLayout {
    var placements: [MasonryPlacement]
    var contentHeight: CGFloat
}

struct MasonryPlacement: Identifiable {
    var id: UUID { item.id }
    var item: ClipboardHistoryItem
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
}
