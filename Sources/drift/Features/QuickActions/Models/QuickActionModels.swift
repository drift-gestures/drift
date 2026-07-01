import SwiftUI

/// Geometry and reading direction for a surface placed near the cursor without leaving its display.
struct OverlaySurfacePlacement {
    /// Center point where the overlay should appear.
    var center: CGPoint
    /// Horizontal growth direction for overlay content.
    var horizontalFlow: MasonryHorizontalFlow
    /// Vertical growth direction for overlay content.
    var verticalFlow: MasonryVerticalFlow
}

/// Determines which display edge the masonry content grows away from.
enum MasonryHorizontalFlow: Equatable {
    /// Content grows from the left edge toward the right edge.
    case leftToRight
    /// Content grows from the right edge toward the left edge.
    case rightToLeft
}

/// Determines whether content is anchored above or below the cursor.
enum MasonryVerticalFlow: Equatable {
    /// Content starts at the top and grows downward.
    case topToBottom
    /// Content starts at the bottom and grows upward.
    case bottomToTop
}

/// The two sections selected by the edge-swipe progress.
enum QuickActionSection: String, CaseIterable, Identifiable {
    /// Clipboard history section.
    case clipboard
    /// Emoji picker section.
    case emoji

    /// Stable identifier used by SwiftUI collection rendering.
    var id: String { rawValue }

    /// Human-readable section title.
    var title: String {
        switch self {
        case .clipboard: "Clipboard"
        case .emoji: "Emoji"
        }
    }

    /// SF Symbol used to represent the section.
    var systemImage: String {
        switch self {
        case .clipboard: "clipboard.fill"
        case .emoji: "face.smiling.fill"
        }
    }

    /// Static prototype items for sections that do not load their own data.
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
    /// Stable identity for SwiftUI rendering.
    let id = UUID()
    /// Primary display text.
    var title: String
    /// Secondary display text.
    var subtitle: String
    /// SF Symbol name associated with the item.
    var systemImage: String
}

/// A precomputed layout used because the cards must mirror and reverse with overlay placement.
struct MasonryLayout {
    /// Positioned card placements.
    var placements: [MasonryPlacement]
    /// Total content height used for bottom-to-top reversal.
    var contentHeight: CGFloat
}

/// Position and size for one clipboard history card in the masonry layout.
struct MasonryPlacement: Identifiable {
    /// Stable identity forwarded from the placed clipboard item.
    var id: UUID { item.id }
    /// Clipboard item displayed at this placement.
    var item: ClipboardHistoryItem
    /// Left edge of the card in local coordinates.
    var x: CGFloat
    /// Top edge of the card in local coordinates.
    var y: CGFloat
    /// Card width.
    var width: CGFloat
    /// Card height.
    var height: CGFloat
}
